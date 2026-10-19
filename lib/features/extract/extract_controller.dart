import 'package:flutter/foundation.dart';

import '../../domain/export/extract_items.dart';
import '../../domain/model/models.dart';
import '../canvas/canvas_ui_state.dart';
import '../canvas/engine/scene.dart';
import '../canvas/marks/mark_layers.dart';

/// What the Extract panel shows and does for the open document: the list,
/// kept current as marks and pages change, and the actions on an item.
class ExtractController {
  ExtractController({
    required this.highlights,
    required this.scene,
    required this.onJump,
    required this.onDelete,
    required this.onUndo,
  });

  final HighlightLayer highlights;
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
  Listenable get changes => Listenable.merge([highlights, scene]);

  Map<String, int> get _pageIndex => {
    for (final c in scene.value.cards) c.id: c.index,
  };

  /// All items for [filter], in reading order.
  List<ExtractItem> items(ExtractFilter filter) => switch (filter) {
    ExtractFilter.notes => const [], // notes arrive with M4
    ExtractFilter.all => buildExtract(highlights.all, _pageIndex),
    ExtractFilter.claim => buildExtract(
      highlights.all,
      _pageIndex,
      only: Meaning.claim,
    ),
    ExtractFilter.method => buildExtract(
      highlights.all,
      _pageIndex,
      only: Meaning.method,
    ),
    ExtractFilter.question => buildExtract(
      highlights.all,
      _pageIndex,
      only: Meaning.question,
    ),
  };
}
