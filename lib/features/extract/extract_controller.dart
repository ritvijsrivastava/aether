import 'package:flutter/foundation.dart';

import '../../domain/export/extract_items.dart';
import '../../domain/model/models.dart';
import '../canvas/canvas_ui_state.dart';
import '../canvas/engine/scene.dart';
import '../canvas/links/links_layer.dart';
import '../canvas/marks/mark_layers.dart';
import '../canvas/notes/notes_layer.dart';

/// What the Extract panel shows and does for the open document: the list,
/// kept current as marks and pages change, and the actions on an item.
class ExtractController {
  ExtractController({
    required this.highlights,
    required this.scene,
    required this.onJump,
    required this.onDelete,
    required this.onUndo,
    this.notes,
    this.links,
    this.onJumpNote,
    this.onDeleteNote,
  });

  final HighlightLayer highlights;

  /// The document's notes and the links from them to highlights.
  final NotesLayer? notes;
  final LinksLayer? links;

  /// Tap on a note's item: take the canvas to it. And its delete control.
  final void Function(Note)? onJumpNote;
  final void Function(Note)? onDeleteNote;
  final ValueListenable<Scene> scene;

  /// Tap on an item: take the canvas to it.
  final void Function(Highlight) onJump;

  /// The delete control on an item.
  final void Function(Highlight) onDelete;

  /// The Undo offered after a delete.
  final VoidCallback onUndo;

  /// Bumped when a jump should get the phone's Extract sheet out of the way.
  final ValueNotifier<int> collapseRequests = ValueNotifier(0);

  /// Fires when the list may have changed.
  Listenable get changes =>
      Listenable.merge([highlights, scene, ?notes, ?links]);

  Map<String, int> get _pageIndex => {
    for (final c in scene.value.cards) c.id: c.index,
  };

  /// All items for [filter], in reading order.
  List<ExtractItem> items(ExtractFilter filter) {
    if (filter == ExtractFilter.notes) return const []; // in [entries]
    return buildExtract(
      highlights.all,
      _pageIndex,
      onlyColor: filter.isColour ? filter.color : null,
    );
  }

  /// The colours in use, in the order they first appear in reading order,
  /// each with how many highlights have it.
  List<(int, int)> colours() {
    final counts = <int, int>{};
    for (final i in buildExtract(highlights.all, _pageIndex)) {
      counts[i.color] = (counts[i.color] ?? 0) + 1;
    }
    return [for (final e in counts.entries) (e.key, e.value)];
  }
}

extension ExtractEntries on ExtractController {
  /// The notes with text, in reading order, each with the quotes it is linked
  /// to.
  List<ExtractNote> noteItems() {
    final n = notes;
    if (n == null) return const [];
    final pages = _pageIndex;
    return buildNotes(n.all, pages, (noteId) {
      final out = <LinkedQuote>[];
      for (final l in links?.forNote(noteId) ?? const <Link>[]) {
        final h = highlights.byId(l.toHighlightId);
        if (h == null) continue;
        out.add(
          LinkedQuote(
            highlightId: h.id,
            quote: h.quote,
            pageIndex: pages[h.pageId] ?? -1,
            isRegion: h.startChar < 0,
          ),
        );
      }
      return out;
    });
  }

  /// What the panel lists for [filter]: highlights, notes, or both in page
  /// order for All.
  List<ExtractEntry> entries(ExtractFilter filter) => switch (filter) {
    ExtractFilter.notes => noteItems(),
    ExtractFilter.all => mergeEntries(items(ExtractFilter.all), noteItems()),
    _ => items(filter),
  };
}
