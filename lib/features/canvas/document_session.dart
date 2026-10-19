import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/hlc/hlc.dart';
import '../../core/id/id_generator.dart';
import '../../data/db/database.dart';
import '../../domain/commands/command.dart';
import '../../domain/commands/command_bus.dart';
import '../../domain/model/models.dart';
import '../../domain/ops/op.dart';
import '../../domain/ops/op_store.dart';
import '../../domain/text/page_text.dart';
import '../../domain/text/text_selection.dart';
import 'engine/canvas_controller.dart';
import 'engine/scene.dart';
import 'engine/view_state.dart';
import 'marks/mark_layers.dart';
import 'marks/mark_tool.dart';

/// An open document: its pages on the canvas, its own undo history, and its
/// remembered view.
///
/// Card moves made by dragging are saved as undoable commands; undo and redo
/// reload the page positions into the canvas. The view (pan and zoom) is saved
/// shortly after it stops changing, and restored on the next open.
class DocumentSession implements MarkSink {
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
    controller.onCardMoved = (id, delta) =>
        _enqueue(() => _moveCard(id, delta));
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

  /// The document's highlights, kept in step with the store. Painters and the
  /// Extract list listen to it.
  final HighlightLayer highlights = HighlightLayer();

  Future<void> _tail = Future.value();
  Timer? _viewTimer;
  bool _viewDirty = false;
  bool _disposed = false;
  bool _closing = false;

  /// Loads the document and puts its pages on the canvas. Returns false if it
  /// does not exist or was deleted.
  Future<bool> load() async {
    final e = await store.entity(docId);
    if (e == null || e.deleted || e.kind != EntityKind.document) return false;
    document = Document.fromState(e);
    controller.scene.value = await _sceneFromStore();
    await _reloadMarks();
    return true;
  }

  Future<void> _reloadMarks() async {
    final entities = await store.entities(kind: EntityKind.mark, docId: docId);
    final all = <Highlight>[];
    for (final e in entities) {
      final m = Mark.fromState(e);
      if (m is Highlight) all.add(m);
    }
    if (!_disposed) highlights.replaceAll(all);
  }

  Future<Scene> _sceneFromStore() async {
    final pages = [
      for (final e in await store.entities(kind: EntityKind.page, docId: docId))
        PageRef.fromState(e),
    ]..sort((a, b) => a.index.compareTo(b.index));
    return Scene([
      for (final p in pages)
        Card(
          id: p.id,
          index: p.index,
          rect: Rect.fromLTWH(p.cardX, p.cardY, p.width, p.height),
        ),
    ]);
  }

  /// Page sizes in order, for the renderer.
  List<Size> pageSizes() => [
    for (final c in controller.scene.value.cards) c.rect.size,
  ];

  // --- card moves and history -------------------------------------------------

  /// Runs [job] after everything already queued, so rapid drags and undos
  /// apply in the order they happened.
  Future<void> _enqueue(Future<void> Function() job) {
    final next = _tail
        .then((_) => _disposed ? null : job())
        .catchError((Object _) {});
    _tail = next;
    return next;
  }

  Future<void> _moveCard(String pageId, Offset delta) async {
    final e = await store.entity(pageId);
    if (e == null) return;
    final p = PageRef.fromState(e);
    await bus.run(
      await _factory.setFields(pageId, {
        F.cardX: p.cardX + delta.dx,
        F.cardY: p.cardY + delta.dy,
      }, label: 'Move page'),
    );
  }

  Future<void> undo() => _enqueue(() async {
    if (await bus.undo()) await _reloadAll();
  });

  Future<void> redo() => _enqueue(() async {
    if (await bus.redo()) await _reloadAll();
  });

  Future<void> _reloadAll() async {
    controller.scene.value = await _sceneFromStore();
    await _reloadMarks();
  }

  // --- highlights ---------------------------------------------------------------

  Highlight _highlight(
    String id,
    String pageId,
    MarkSelection s,
    Meaning meaning,
    PageText? text,
  ) => Highlight(
    id: id,
    docId: docId,
    pageId: pageId,
    meaning: meaning,
    startChar: s.start,
    endChar: s.end,
    quote: s.quote,
    contextBefore: text == null || s.isRegion
        ? ''
        : text.contextBefore(s.start),
    contextAfter: text == null || s.isRegion ? '' : text.contextAfter(s.end),
    rects: s.rects,
  );

  /// Shows the highlight at once and saves it behind the queue. If the save
  /// fails the highlight is taken back off the page, never left looking
  /// saved when it is not.
  @override
  String addHighlight({
    required String pageId,
    required MarkSelection selection,
    required Meaning meaning,
    PageText? text,
  }) {
    final id = ids.next();
    final h = _highlight(id, pageId, selection, meaning, text);
    highlights.add(h);
    _enqueue(() async {
      try {
        await bus.run(
          _factory.create(
            EntityKind.mark,
            id,
            h.toFields(),
            label: 'Highlight',
          ),
        );
      } catch (e, st) {
        debugPrint('Saving highlight $id failed: $e\n$st');
        highlights.remove(id);
      }
    });
    return id;
  }

  /// Removes a highlight from the page at once; undoable.
  void deleteHighlight(String id) {
    final old = highlights.byId(id);
    if (old == null) return;
    highlights.remove(id);
    _enqueue(() async {
      try {
        await bus.run(await _factory.delete(id, label: 'Delete highlight'));
      } catch (e, st) {
        debugPrint('Deleting highlight $id failed: $e\n$st');
        highlights.add(old);
      }
    });
  }

  @override
  String replaceHighlight({
    required String oldId,
    required String pageId,
    required MarkSelection selection,
    required Meaning meaning,
    PageText? text,
  }) {
    final id = ids.next();
    final h = _highlight(id, pageId, selection, meaning, text);
    final old = highlights.byId(oldId);
    highlights
      ..remove(oldId)
      ..add(h);
    _enqueue(() async {
      try {
        await bus.run(
          Command.group('Highlight', [
            await _factory.delete(oldId),
            _factory.create(EntityKind.mark, id, h.toFields()),
          ]),
        );
      } catch (e, st) {
        debugPrint('Replacing highlight $oldId failed: $e\n$st');
        highlights.remove(id);
        if (old != null) highlights.add(old);
      }
    });
    return id;
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
    controller.onCardMoved = null;
    _viewTimer?.cancel();
    await _saveView();
    _disposed = true;
    bus.dispose();
  }
}
