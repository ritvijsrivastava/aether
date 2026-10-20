import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/hlc/hlc.dart';
import '../../core/id/id_generator.dart';
import '../../data/db/database.dart';
import '../../domain/commands/command.dart';
import '../../domain/commands/command_bus.dart';
import '../../domain/marks/highlight_rules.dart';
import '../../domain/model/models.dart';
import '../../domain/ops/op.dart';
import '../../domain/ops/op_store.dart';
import '../../domain/text/page_text.dart';
import '../../domain/text/text_selection.dart';
import 'canvas_ui_state.dart' show CanvasTool;
import 'engine/canvas_controller.dart';
import 'engine/scene.dart';
import 'engine/view_state.dart';
import 'ink/ink_layer.dart';
import 'erase/erase_tool.dart';
import 'ink/ink_tool.dart';
import 'links/link_tool.dart';
import 'links/links_layer.dart';
import 'marks/mark_layers.dart';
import 'notes/note_tool.dart';
import 'select/select_tool.dart';
import 'select/selection.dart';
import 'notes/notes_layer.dart';
import 'marks/mark_tool.dart';

/// An open document: its pages on the canvas, its own undo history, and its
/// remembered view.
///
/// Card moves made by dragging are saved as undoable commands; undo and redo
/// reload the page positions into the canvas. The view (pan and zoom) is saved
/// shortly after it stops changing, and restored on the next open.
class DocumentSession
    implements
        MarkSink,
        InkSink,
        EraseSink,
        NoteSink,
        NoteActions,
        LinkSink,
        SelectSink {
  DocumentSession({
    required this.docId,
    required this.store,
    required this.db,
    required this.controller,
    required HlcClock clock,
    required this.ids,
    this.viewSaveDelay = const Duration(milliseconds: 600),
    this.noteEditDelay = const Duration(milliseconds: 800),
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

  /// Typing in a note is saved after this much quiet (or when it loses focus).
  final Duration noteEditDelay;
  final CommandFactory _factory;

  Document? document;

  /// The document's highlights, kept in step with the store. Painters and the
  /// Extract list listen to it.
  final HighlightLayer highlights = HighlightLayer();

  /// The document's ink strokes.
  final InkLayer ink = InkLayer();

  /// The document's notes, drafts included.
  final NotesLayer notes = NotesLayer();

  /// The links between notes and highlights.
  final LinksLayer links = LinksLayer();

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
    final strokes = <Ink>[];
    final saved = <Note>[];
    for (final e in entities) {
      final m = Mark.fromState(e);
      if (m is Highlight) all.add(m);
      if (m is Ink) strokes.add(m);
      if (m is Note) saved.add(m);
    }
    final linkEntities = await store.entities(
      kind: EntityKind.link,
      docId: docId,
    );
    if (!_disposed) {
      highlights.replaceAll(all);
      ink.replaceAll(strokes);
      notes.replaceSaved(saved);
      links.replaceAll([for (final e in linkEntities) Link.fromState(e)]);
    }
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
    int color,
    PageText? text,
  ) => Highlight(
    id: id,
    docId: docId,
    pageId: pageId,
    color: color,
    startChar: s.start,
    endChar: s.end,
    quote: s.quote,
    contextBefore: text == null || s.isRegion
        ? ''
        : text.contextBefore(s.start),
    contextAfter: text == null || s.isRegion ? '' : text.contextAfter(s.end),
    rects: s.rects,
  );

  /// Called with a highlight the owner has just made or touched again (a
  /// duplicate, a merge, a recolour): the screen shows its action strip.
  void Function(Highlight)? onHighlightTouched;

  /// A stroke, wipe or highlight just finished with this tool: the screen
  /// may fold the tool's options away.
  void Function(CanvasTool)? onGestureDone;

  void _touched(String id) {
    final h = highlights.byId(id);
    if (h != null) onHighlightTouched?.call(h);
    onGestureDone?.call(CanvasTool.mark);
  }

  /// Marks [selection]. Re-marking the same words in the same colour does
  /// nothing new (the existing highlight is reported through
  /// [onHighlightTouched]); the same words in another colour change that
  /// highlight's colour; overlapping highlights of one colour merge into one.
  ///
  /// Shows the result at once and saves it behind the queue. If the save
  /// fails it is taken back, never left looking saved when it is not.
  @override
  String addHighlight({
    required String pageId,
    required MarkSelection selection,
    required int color,
    PageText? text,
  }) {
    final plan = planHighlight(highlights.forPage(pageId), selection, color);
    switch (plan) {
      case HighlightDuplicate(:final existing):
        _touched(existing.id);
        return existing.id;
      case HighlightRecolor(:final existing):
        recolorMarks([
          MarkRef(MarkKind.highlight, existing.id),
        ], highlightColor: color);
        _touched(existing.id);
        return existing.id;
      case HighlightMerge(:final absorbed, :final start, :final end):
        final union = text == null
            ? null
            : TextSelector.fromRange(text, start, end);
        if (union != null) {
          final id = ids.next();
          _swapHighlights([
            for (final h in absorbed) h.id,
          ], _highlight(id, pageId, union, color, text));
          _touched(id);
          return id;
        }
      case HighlightAdd():
        break;
    }
    final id = ids.next();
    final h = _highlight(id, pageId, selection, color, text);
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
    _touched(id);
    return id;
  }

  /// Shows the stroke at once and saves it behind the queue; one undo step.
  @override
  String addInk({
    String? pageId,
    required Float32List samples,
    required double width,
    required int color,
  }) {
    final id = ids.next();
    final stroke = Ink(
      id: id,
      docId: docId,
      pageId: pageId,
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

  /// Changes the colour of the selected highlights and/or the colour of the
  /// selected ink, as one step.
  void recolorMarks(
    Iterable<MarkRef> refs, {
    int? highlightColor,
    int? inkColor,
  }) {
    final finals = <Mark>[];
    for (final r in refs) {
      if (r.kind == MarkKind.highlight && highlightColor != null) {
        final h = highlights.byId(r.id);
        if (h != null && h.color != highlightColor) {
          final next = h.copyWith(color: highlightColor);
          highlights.add(next);
          finals.add(next);
        }
      } else if (r.kind == MarkKind.ink && inkColor != null) {
        final s = ink.byId(r.id);
        if (s != null && s.color != inkColor) {
          final next = s.copyWith(color: inkColor);
          ink.add(next);
          finals.add(next);
        }
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

  /// Deletes the given marks (and links to them) as one undoable step.
  void deleteMarks(Iterable<MarkRef> refs) {
    final ids = <String>{};
    final linkIds = <String>{};
    for (final r in refs) {
      switch (r.kind) {
        case MarkKind.highlight:
          if (highlights.byId(r.id) == null) continue;
          highlights.remove(r.id);
          linkIds.addAll(links.forHighlight(r.id).map((l) => l.id));
        case MarkKind.ink:
          if (ink.byId(r.id) == null) continue;
          ink.remove(r.id);
        case MarkKind.note:
          final n = notes.byId(r.id);
          if (n == null) continue;
          final wasDraft = notes.isDraft(r.id);
          _noteTimers.remove(r.id)?.cancel();
          notes.remove(r.id);
          linkIds.addAll(links.forNote(r.id).map((l) => l.id));
          if (wasDraft) continue;
      }
      ids.add(r.id);
    }
    for (final l in linkIds) {
      links.remove(l);
    }
    if (ids.isEmpty && linkIds.isEmpty) return;
    _enqueue(() async {
      try {
        await bus.run(
          Command.group(
            ids.length == 1 ? 'Delete mark' : 'Delete ${ids.length} marks',
            [
              for (final id in ids) await _factory.delete(id),
              for (final l in linkIds) await _factory.delete(l),
            ],
          ),
        );
      } catch (e, st) {
        debugPrint('Deleting marks failed: $e\n$st');
        await _reloadMarks();
      }
    });
  }

  // --- links -------------------------------------------------------------------

  @override
  void addLink(String noteId, String highlightId) {
    if (links.between(noteId, highlightId) != null) return;
    final note = notes.byId(noteId);
    if (note == null || highlights.byId(highlightId) == null) return;
    // A note with text still being typed is written first, so the link has
    // something to point at.
    if (notes.isDraft(noteId)) {
      if (note.text.trim().isEmpty) return;
      unawaited(saveNote(noteId));
    }
    final l = Link(
      id: ids.next(),
      docId: docId,
      fromNoteId: noteId,
      toHighlightId: highlightId,
    );
    links.add(l);
    _enqueue(() async {
      try {
        await bus.run(
          _factory.create(EntityKind.link, l.id, l.toFields(), label: 'Link'),
        );
      } catch (e, st) {
        debugPrint('Saving link ${l.id} failed: $e\n$st');
        links.remove(l.id);
      }
    });
  }

  /// Removes a link; undoable.
  void deleteLink(String id) {
    final l = links.byId(id);
    if (l == null) return;
    links.remove(id);
    _enqueue(() async {
      try {
        await bus.run(await _factory.delete(id, label: 'Remove link'));
      } catch (e, st) {
        debugPrint('Removing link $id failed: $e\n$st');
        links.add(l);
      }
    });
  }

  /// Removes every link of [noteId] as one undo step.
  void unlinkNote(String noteId) {
    final gone = links.forNote(noteId);
    if (gone.isEmpty) return;
    for (final l in gone) {
      links.remove(l.id);
    }
    _enqueue(() async {
      try {
        await bus.run(
          Command.group('Unlink', [
            for (final l in gone) await _factory.delete(l.id),
          ]),
        );
      } catch (e, st) {
        debugPrint('Unlinking $noteId failed: $e\n$st');
        for (final l in gone) {
          links.add(l);
        }
      }
    });
  }

  // --- notes ------------------------------------------------------------------

  final Map<String, Timer> _noteTimers = {};

  /// Notes that were added "to a highlight" and are to be linked to it as soon
  /// as they have text and are saved.
  final Map<String, String> _pendingLinks = {};

  @override
  String beginNote({
    String? pageId,
    required double x,
    required double y,
    String? linkToHighlight,
  }) {
    final id = ids.next();
    if (linkToHighlight != null) _pendingLinks[id] = linkToHighlight;
    notes.add(
      Note(id: id, docId: docId, pageId: pageId, x: x, y: y),
      draft: true,
    );
    notes.requestFocus(id);
    return id;
  }

  /// The text of a note changed. It shows at once; it is saved when typing
  /// pauses, so one burst of typing is one undo step.
  @override
  void editNoteText(String id, String text) {
    final n = notes.byId(id);
    if (n == null || n.text == text) return;
    notes.update(n.copyWith(text: text));
    _noteTimers[id]?.cancel();
    _noteTimers[id] = Timer(noteEditDelay, () => saveNote(id));
  }

  /// Writes a note's current state: creates it the first time (a draft with
  /// text), edits it afterwards. A note with no text is not written.
  Future<void> saveNote(String id) {
    _noteTimers.remove(id)?.cancel();
    return _enqueue(() async {
      final n = notes.byId(id);
      if (n == null) return;
      try {
        if (notes.isDraft(id)) {
          if (n.text.trim().isEmpty) return;
          notes.promote(id);
          await bus.run(
            _factory.create(EntityKind.mark, id, n.toFields(), label: 'Note'),
          );
          final target = _pendingLinks.remove(id);
          if (target != null) addLink(id, target);
        } else {
          await bus.run(
            await _factory.setFields(id, n.toFields(), label: 'Edit note'),
          );
        }
      } catch (e, st) {
        debugPrint('Saving note $id failed: $e\n$st');
      }
    });
  }

  /// A note is being moved or resized: it shows at once; see
  /// [noteGeometryDone] for the save.
  @override
  void noteGeometryChanged(
    String id, {
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    final n = notes.byId(id);
    if (n == null) return;
    notes.update(n.copyWith(x: x, y: y, width: width, height: height));
  }

  /// A drag of a note is over: one undo step for the whole move or resize.
  @override
  Future<void> noteGeometryDone(String id) =>
      notes.isDraft(id) ? Future.value() : saveNote(id);

  /// The note lost the keyboard: save what was typed; an empty note is thrown
  /// away (with no trace if it was never saved).
  @override
  Future<void> noteBlurred(String id) async {
    final n = notes.byId(id);
    if (n == null) return;
    if (n.text.trim().isEmpty) {
      _noteTimers.remove(id)?.cancel();
      if (notes.isDraft(id)) {
        _pendingLinks.remove(id);
        notes.remove(id);
      } else {
        deleteNote(id);
      }
      return;
    }
    await saveNote(id);
  }

  /// Deletes a note; undoable.
  @override
  void deleteNote(String id) {
    final n = notes.byId(id);
    if (n == null) return;
    final wasDraft = notes.isDraft(id);
    _noteTimers.remove(id)?.cancel();
    final gone = links.forNote(id);
    notes.remove(id);
    for (final l in gone) {
      links.remove(l.id);
    }
    if (wasDraft) return;
    _enqueue(() async {
      try {
        await bus.run(
          Command.group('Delete note', [
            await _factory.delete(id),
            for (final l in gone) await _factory.delete(l.id),
          ]),
        );
      } catch (e, st) {
        debugPrint('Deleting note $id failed: $e\n$st');
        notes.add(n);
        for (final l in gone) {
          links.add(l);
        }
      }
    });
  }

  /// Saves one erase as a single undo step. The page already shows the result;
  /// if the save fails the page is reloaded from what was really stored.
  @override
  void commitErase({required Set<String> deleted, required List<Ink> created}) {
    if (deleted.isNotEmpty || created.isNotEmpty) {
      onGestureDone?.call(CanvasTool.erase);
    }
    // Links to highlights that were wiped go with them.
    final gone = [for (final id in deleted) ...links.forHighlight(id)];
    for (final l in gone) {
      links.remove(l.id);
    }
    _enqueue(() async {
      try {
        final parts = <Command>[
          for (final id in deleted) await _factory.delete(id),
          for (final l in gone) await _factory.delete(l.id),
          for (final c in created)
            _factory.create(EntityKind.mark, c.id, c.toFields()),
        ];
        await bus.run(Command.group('Erase', parts));
      } catch (e, st) {
        debugPrint('Saving an erase failed: $e\n$st');
        await _reloadMarks();
      }
    });
  }

  /// Removes a highlight from the page at once; undoable.
  void deleteHighlight(String id) {
    final old = highlights.byId(id);
    if (old == null) return;
    final gone = links.forHighlight(id);
    highlights.remove(id);
    for (final l in gone) {
      links.remove(l.id);
    }
    _enqueue(() async {
      try {
        await bus.run(
          Command.group('Delete highlight', [
            await _factory.delete(id),
            for (final l in gone) await _factory.delete(l.id),
          ]),
        );
      } catch (e, st) {
        debugPrint('Deleting highlight $id failed: $e\n$st');
        highlights.add(old);
        for (final l in gone) {
          links.add(l);
        }
      }
    });
  }

  /// Replaces [oldId] with [selection] as one undoable step (a double tap
  /// widening a word to its sentence). If [oldId] is not inside the new
  /// selection (it was a larger highlight that the tap only re-found), the
  /// selection is marked as a new highlight instead and nothing is lost.
  @override
  String replaceHighlight({
    required String oldId,
    required String pageId,
    required MarkSelection selection,
    required int color,
    PageText? text,
  }) {
    final old = highlights.byId(oldId);
    final inside =
        old != null &&
        old.startChar >= selection.start &&
        old.endChar <= selection.end;
    if (!inside) {
      return addHighlight(
        pageId: pageId,
        selection: selection,
        color: color,
        text: text,
      );
    }
    // Other highlights of this colour the sentence now covers merge in too.
    final absorbed = [
      oldId,
      for (final h in highlights.forPage(pageId))
        if (h.id != oldId &&
            h.color == color &&
            h.startChar >= 0 &&
            h.startChar < selection.end &&
            selection.start < h.endChar)
          h.id,
    ];
    final id = ids.next();
    _swapHighlights(absorbed, _highlight(id, pageId, selection, color, text));
    _touched(id);
    return id;
  }

  /// Replaces the highlights [oldIds] with [h] in one undo step. Links to
  /// the old ones follow to [h] (once per note).
  void _swapHighlights(List<String> oldIds, Highlight h) {
    final id = h.id;
    final olds = [
      for (final o in oldIds)
        if (highlights.byId(o) != null) highlights.byId(o)!,
    ];
    final moved = [for (final o in oldIds) ...links.forHighlight(o)];
    final seen = <String>{};
    final repointed = [
      for (final l in moved)
        if (seen.add(l.fromNoteId))
          Link(
            id: ids.next(),
            docId: docId,
            fromNoteId: l.fromNoteId,
            toHighlightId: id,
          ),
    ];
    for (final o in oldIds) {
      highlights.remove(o);
    }
    highlights.add(h);
    for (final l in moved) {
      links.remove(l.id);
    }
    for (final l in repointed) {
      links.add(l);
    }
    _enqueue(() async {
      try {
        await bus.run(
          Command.group('Highlight', [
            for (final o in oldIds) await _factory.delete(o),
            for (final l in moved) await _factory.delete(l.id),
            _factory.create(EntityKind.mark, id, h.toFields()),
            for (final l in repointed)
              _factory.create(EntityKind.link, l.id, l.toFields()),
          ]),
        );
      } catch (e, st) {
        debugPrint('Replacing highlights $oldIds failed: $e\n$st');
        highlights.remove(id);
        for (final o in olds) {
          highlights.add(o);
        }
        for (final l in repointed) {
          links.remove(l.id);
        }
        for (final l in moved) {
          links.add(l);
        }
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
    controller.onCardMoved = null;
    _viewTimer?.cancel();
    // Leaving the screen right after a mark must not lose it: save pending
    // note text, then let every queued save finish before closing the queue.
    for (final id in _noteTimers.keys.toList()) {
      unawaited(saveNote(id));
    }
    await _tail;
    await _saveView();
    _disposed = true;
    bus.dispose();
  }
}
