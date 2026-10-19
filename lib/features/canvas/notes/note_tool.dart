import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../engine/scene.dart';
import '../engine/view_state.dart';
import '../input/tool_gestures.dart';

/// Where a tapped-in note goes.
abstract interface class NoteSink {
  /// Puts an empty draft note at ([x], [y]) (page space, or canvas space for a
  /// null [pageId]) and focuses it. Returns its id.
  ///
  /// With [linkToHighlight], the note is linked to that highlight as soon as
  /// it has text and is saved.
  String beginNote({
    String? pageId,
    required double x,
    required double y,
    String? linkToHighlight,
  });
}

/// What a note on the page can ask of the document.
abstract interface class NoteActions {
  /// The text changed (saved when typing pauses).
  void editNoteText(String id, String text);

  /// The note is being moved or resized; shows at once.
  void noteGeometryChanged(
    String id, {
    double? x,
    double? y,
    double? width,
    double? height,
  });

  /// The move or resize ended: save it as one step.
  Future<void> noteGeometryDone(String id);

  /// The note lost the keyboard: save it, or throw it away if empty.
  Future<void> noteBlurred(String id);

  void deleteNote(String id);
}

/// The Note tool: tap to place a note, which takes the keyboard at once.
///
/// A drag with the tool places nothing (it would be a slip of the pen).
class NoteToolController implements ToolHandler {
  NoteToolController({required this.view, required this.scene, this.sink});

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  NoteSink? sink;

  /// Movement beyond this many dp makes it a drag, not a tap.
  static const double tapSlopPx = 8;

  Offset? _down;
  bool _moved = false;

  @override
  void start(ToolPoint p) {
    _down = p.position;
    _moved = false;
  }

  @override
  void move(ToolPoint p) {
    final d = _down;
    if (d != null && (p.position - d).distance > tapSlopPx) _moved = true;
  }

  @override
  void end(ToolPoint p) {
    final d = _down;
    _down = null;
    if (d == null || _moved || sink == null) return;
    final world = view.value.screenToWorld(d);
    Card? card;
    final cards = scene.value.cards;
    for (var i = cards.length - 1; i >= 0; i--) {
      if (cards[i].rect.contains(world)) {
        card = cards[i];
        break;
      }
    }
    final at = card == null ? world : world - card.rect.topLeft;
    sink!.beginNote(pageId: card?.id, x: at.dx, y: at.dy);
  }

  @override
  void cancel() => _down = null;
}
