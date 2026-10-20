import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/hlc/hlc.dart';
import '../../core/id/id_generator.dart';
import '../../data/db/database.dart';
import '../../domain/commands/command.dart';
import '../../domain/commands/command_bus.dart';
import '../../domain/model/models.dart';
import '../../domain/ops/op.dart' show EntityKind;
import '../../domain/ops/op_store.dart';
import 'canvas_ui_state.dart' show CanvasTool;
import 'engine/canvas_controller.dart';
import 'engine/view_state.dart';
import 'ink/ink_layer.dart';
import 'erase/erase_tool.dart';
import 'ink/ink_tool.dart';
import 'select/selection.dart' show MarkKind, MarkRef;
import 'select/select_tool.dart';

/// An open board: its ink, its undo history, and its remembered view.
///
/// Strokes show at once and are saved behind a queue; undo and redo re-read
/// the ink from the store. The view (pan and zoom) is saved shortly after it
/// stops changing, and restored on the next open.
///
class DocumentSession implements InkSink, EraseSink, SelectSink {
  DocumentSession({
    required this.docId,
    required this.store,
    required this.db,
    required this.controller,
    required HlcClock clock,
    required this.ids,
    this.viewSaveDelay = const Duration(milliseconds: 600),
  }) : bus = CommandBus(store: store, clock: clock, ids: ids),
       _factory = CommandFactory(store) {
    controller.view.addListener(_viewChanged);
  }

  final String docId;
  final OpStore store;
  final AetherDatabase db;
  final CanvasController controller;
  final IdGenerator ids;
  final CommandBus bus;
  final Duration viewSaveDelay;
  final CommandFactory _factory;

  Document? document;

  /// The board's ink strokes, all in world space.
  final InkLayer ink = InkLayer();

  Future<void> _tail = Future.value();
  Timer? _viewTimer;
  bool _viewDirty = false;
  bool _disposed = false;
  bool _closing = false;

  /// Loads the document and its ink. Returns false if it does not exist or
  /// was deleted.
  Future<bool> load() async {
    final e = await store.entity(docId);
    if (e == null || e.deleted || e.kind != EntityKind.document) return false;
    document = Document.fromState(e);
    await _reloadMarks();
    return true;
  }

  Future<void> _reloadMarks() async {
    final entities = await store.entities(kind: EntityKind.mark, docId: docId);
    final strokes = <Ink>[];
    for (final e in entities) {
      final m = Mark.fromState(e);
      if (m is! Ink) continue;
      strokes.add(m);
    }
    if (!_disposed) ink.replaceAll(strokes);
  }

  /// Runs [job] after everything already queued, so rapid actions apply in
  /// the order they happened.
  Future<void> _enqueue(Future<void> Function() job) {
    final next = _tail
        .then((_) => _disposed ? null : job())
        .catchError((Object _) {});
    _tail = next;
    return next;
  }

  Future<void> undo() => _enqueue(() async {
    if (await bus.undo()) await _reloadMarks();
  });

  Future<void> redo() => _enqueue(() async {
    if (await bus.redo()) await _reloadMarks();
  });

  /// A stroke, wipe or selection edit just finished: the screen may fold the
  /// tool's options away.
  void Function(CanvasTool)? onGestureDone;

  // --- ink --------------------------------------------------------------------

  /// Shows the stroke at once and saves it behind the queue; one undo step.
  @override
  String addInk({
    required Float32List samples,
    required double width,
    required int color,
  }) {
    final id = ids.next();
    final stroke = Ink(
      id: id,
      docId: docId,
      samples: samples,
      width: width,
      color: color,
    );
    ink.add(stroke);
    onGestureDone?.call(CanvasTool.ink);
    _enqueue(() async {
      try {
        await bus.run(
          _factory.create(EntityKind.mark, id, stroke.toFields(), label: 'Ink'),
        );
      } catch (e, st) {
        debugPrint('Saving ink $id failed: $e\n$st');
        ink.remove(id);
      }
    });
    return id;
  }

  @override
  String newId() => ids.next();

  // --- selection edits ---------------------------------------------------------

  @override
  void commitMove(List<Mark> finals) => _saveMarkEdits(finals, 'Move');

  /// Changes the colour of the selected ink as one step.
  void recolorMarks(Iterable<MarkRef> refs, {int? inkColor}) {
    final finals = <Mark>[];
    for (final r in refs) {
      if (r.kind != MarkKind.ink || inkColor == null) continue;
      final s = ink.byId(r.id);
      if (s != null && s.color != inkColor) {
        final next = s.copyWith(color: inkColor);
        ink.add(next);
        finals.add(next);
      }
    }
    _saveMarkEdits(finals, 'Recolor');
  }

  void _saveMarkEdits(List<Mark> finals, String label) {
    if (finals.isEmpty) return;
    _enqueue(() async {
      try {
        await bus.run(
          Command.group(label, [
            for (final m in finals)
              await _factory.setFields(m.id, m.toFields()),
          ]),
        );
      } catch (e, st) {
        debugPrint('Saving $label failed: $e\n$st');
        await _reloadMarks();
      }
    });
  }

  /// Deletes the given strokes as one undoable step.
  void deleteMarks(Iterable<MarkRef> refs) {
    final ids = <String>[];
    for (final r in refs) {
      if (r.kind != MarkKind.ink) continue;
      if (ink.byId(r.id) == null) continue;
      ink.remove(r.id);
      ids.add(r.id);
    }
    if (ids.isEmpty) return;
    _enqueue(() async {
      try {
        await bus.run(
          Command.group(
            ids.length == 1 ? 'Delete stroke' : 'Delete ${ids.length} strokes',
            [for (final id in ids) await _factory.delete(id)],
          ),
        );
      } catch (e, st) {
        debugPrint('Deleting strokes failed: $e\n$st');
        await _reloadMarks();
      }
    });
  }

  /// Saves one erase as a single undo step. The page already shows the result;
  /// if the save fails the ink is reloaded from what was really stored.
  @override
  void commitErase({required Set<String> deleted, required List<Ink> created}) {
    if (deleted.isNotEmpty || created.isNotEmpty) {
      onGestureDone?.call(CanvasTool.erase);
    }
    _enqueue(() async {
      try {
        await bus.run(
          Command.group('Erase', [
            for (final id in deleted) await _factory.delete(id),
            for (final c in created)
              _factory.create(EntityKind.mark, c.id, c.toFields()),
          ]),
        );
      } catch (e, st) {
        debugPrint('Saving an erase failed: $e\n$st');
        await _reloadMarks();
      }
    });
  }

  /// Completes when every queued save has been written.
  Future<void> settled() => _tail;

  // --- remembered view --------------------------------------------------------

  Future<ViewState?> savedView() async {
    final row = await db.viewState(docId);
    return row == null ? null : ViewState(x: row.x, y: row.y, zoom: row.zoom);
  }

  void _viewChanged() {
    _viewDirty = true;
    _viewTimer?.cancel();
    _viewTimer = Timer(viewSaveDelay, _saveView);
  }

  Future<void> _saveView() async {
    if (!_viewDirty) return;
    _viewDirty = false;
    final v = controller.view.value;
    await db.putViewState(docId, v.x, v.y, v.zoom);
  }

  Future<void> dispose() async {
    if (_closing) return;
    _closing = true;
    controller.view.removeListener(_viewChanged);
    _viewTimer?.cancel();
    await _tail;
    await _saveView();
    _disposed = true;
    bus.dispose();
  }
}
