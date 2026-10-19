import 'dart:async';
import 'dart:ui';

import '../../core/hlc/hlc.dart';
import '../../core/id/id_generator.dart';
import '../../data/db/database.dart';
import '../../domain/commands/command.dart';
import '../../domain/commands/command_bus.dart';
import '../../domain/model/models.dart';
import '../../domain/ops/op.dart';
import '../../domain/ops/op_store.dart';
import 'engine/canvas_controller.dart';
import 'engine/scene.dart';
import 'engine/view_state.dart';

/// An open document: its pages on the canvas, its own undo history, and its
/// remembered view.
///
/// Card moves made by dragging are saved as undoable commands; undo and redo
/// reload the page positions into the canvas. The view (pan and zoom) is saved
/// shortly after it stops changing, and restored on the next open.
class DocumentSession {
  DocumentSession({
    required this.docId,
    required this.store,
    required this.db,
    required this.controller,
    required HlcClock clock,
    required IdGenerator ids,
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
  final CommandBus bus;
  final Duration viewSaveDelay;
  final CommandFactory _factory;

  Document? document;

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
    return true;
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
    if (await bus.undo()) controller.scene.value = await _sceneFromStore();
  });

  Future<void> redo() => _enqueue(() async {
    if (await bus.redo()) controller.scene.value = await _sceneFromStore();
  });

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
