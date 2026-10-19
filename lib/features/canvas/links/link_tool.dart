import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/marks/link_geometry.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';
import '../input/tool_gestures.dart';
import '../marks/mark_layers.dart';
import '../notes/notes_layer.dart';
import 'links_layer.dart';

/// Where a new link goes.
abstract interface class LinkSink {
  /// Joins a note to a highlight (no second link between the same two).
  void addLink(String noteId, String highlightId);
}

/// The Link tool (SPEC 8): drag from a note to a highlight, or from a
/// highlight to a note. The line snaps to the nearest target within 24 dp,
/// which gets a halo while it is in reach. A tap on a link line selects it, so
/// it can be removed.
class LinkToolController implements ToolHandler {
  LinkToolController({
    required this.view,
    required this.scene,
    required this.notes,
    required this.highlights,
    required this.links,
    required this.live,
    this.sink,
  });

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final NotesLayer notes;
  final HighlightLayer highlights;
  final LinksLayer links;
  final LiveLink live;
  LinkSink? sink;

  /// A target within this many dp of the pointer is snapped to.
  static const double snapPx = 24;

  /// A press within this many dp of a link line selects it.
  static const double lineHitPx = 14;

  /// Movement beyond this many dp is a drag.
  static const double tapSlopPx = 8;

  Offset _downScreen = Offset.zero;
  bool _dragging = false;
  bool _active = false;

  // The end the drag started on.
  String? _fromNote, _fromHighlight;

  // The target in reach right now.
  String? _toNote, _toHighlight;

  LinkLayout get _layout =>
      LinkLayout(scene: scene.value, notes: notes, highlights: highlights);

  bool get isActive => _active;

  Card? _cardAt(Offset world, {double inflate = 0}) {
    final cards = scene.value.cards;
    for (var i = cards.length - 1; i >= 0; i--) {
      if (cards[i].rect.inflate(inflate).contains(world)) return cards[i];
    }
    return null;
  }

  String? _noteAt(Offset world) {
    final layout = _layout;
    String? hit;
    for (final n in notes.all) {
      final b = layout.noteBox(n.id);
      if (b != null &&
          LinkGeometry.distanceToBox(b, world) <= 4 / view.value.zoom) {
        hit = n.id;
      }
    }
    return hit;
  }

  String? _highlightAt(Offset world) {
    final card = _cardAt(world);
    if (card == null) return null;
    final local = world - card.rect.topLeft;
    return highlights.hitTest(card.id, local.dx, local.dy, view.value.zoom)?.id;
  }

  /// The link line nearest [world], if one passes within reach.
  String? _lineAt(Offset world) {
    final layout = _layout;
    String? best;
    var bestD = lineHitPx / view.value.zoom;
    for (final l in links.all) {
      final e = layout.ends(l);
      if (e == null) continue;
      final d = LinkGeometry.distanceToCurve(
        world,
        e.note,
        e.control,
        e.highlight,
      );
      if (d <= bestD) {
        bestD = d;
        best = l.id;
      }
    }
    return best;
  }

  @override
  void start(ToolPoint p) {
    if (sink == null) return;
    _active = true;
    _dragging = false;
    _downScreen = p.position;
    _fromNote = _fromHighlight = _toNote = _toHighlight = null;
    final world = view.value.screenToWorld(p.position);
    // A line on top of a note or highlight loses to the thing it joins: the
    // drag starts from the note or highlight, and only a press on bare canvas
    // selects a line.
    _fromNote = _noteAt(world);
    if (_fromNote == null) _fromHighlight = _highlightAt(world);
    if (_fromNote == null && _fromHighlight == null) {
      links.select(_lineAt(world));
      _active = false;
      return;
    }
    links.select(null);
  }

  @override
  void move(ToolPoint p) {
    if (!_active) return;
    if (!_dragging) {
      if ((p.position - _downScreen).distance <= tapSlopPx) return;
      _dragging = true;
      live.begin(view.value.screenToWorld(_downScreen));
    }
    final world = view.value.screenToWorld(p.position);
    _findTarget(world);
    final layout = _layout;
    var to = world;
    var target = const <Rect>[];
    if (_toHighlight != null) {
      final boxes = layout.highlightBoxes(_toHighlight!);
      if (boxes != null) {
        to = LinkGeometry.onHighlight(boxes, world);
        target = [for (final b in boxes) Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1)];
      }
    } else if (_toNote != null) {
      final b = layout.noteBox(_toNote!);
      if (b != null) {
        to = LinkGeometry.edgeToward(b, world);
        target = [Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1)];
      }
    }
    live.update(from: _startAnchor(layout, to), to: to, target: target);
  }

  /// Where the dragged line leaves the end it started on.
  Offset _startAnchor(LinkLayout layout, Offset toward) {
    if (_fromNote != null) {
      final b = layout.noteBox(_fromNote!);
      if (b != null) return LinkGeometry.edgeToward(b, toward);
    }
    if (_fromHighlight != null) {
      final boxes = layout.highlightBoxes(_fromHighlight!);
      if (boxes != null) return LinkGeometry.onHighlight(boxes, toward);
    }
    return view.value.screenToWorld(_downScreen);
  }

  void _findTarget(Offset world) {
    final reach = snapPx / view.value.zoom;
    _toNote = _toHighlight = null;
    final layout = _layout;
    if (_fromNote != null) {
      String? best;
      var bestD = reach;
      for (final card in scene.value.cards) {
        if (!card.rect.inflate(reach).contains(world)) continue;
        final local = world - card.rect.topLeft;
        final h = highlights.nearest(card.id, local.dx, local.dy, reach);
        if (h == null) continue;
        final boxes = layout.highlightBoxes(h.id)!;
        final d = boxes
            .map((b) => LinkGeometry.distanceToBox(b, world))
            .reduce((a, b) => a < b ? a : b);
        if (d <= bestD) {
          bestD = d;
          best = h.id;
        }
      }
      _toHighlight = best;
    } else if (_fromHighlight != null) {
      String? best;
      var bestD = reach;
      for (final n in notes.all) {
        final b = layout.noteBox(n.id);
        if (b == null) continue;
        final d = LinkGeometry.distanceToBox(b, world);
        if (d <= bestD) {
          bestD = d;
          best = n.id;
        }
      }
      _toNote = best;
    }
  }

  @override
  void end(ToolPoint p) {
    if (!_active) return;
    final note = _fromNote ?? _toNote;
    final highlight = _fromHighlight ?? _toHighlight;
    final wasDrag = _dragging;
    _reset();
    if (wasDrag && note != null && highlight != null) {
      sink?.addLink(note, highlight);
    }
  }

  @override
  void cancel() {
    if (_active) _reset();
  }

  void _reset() {
    _active = false;
    _dragging = false;
    _fromNote = _fromHighlight = _toNote = _toHighlight = null;
    live.end();
  }
}
