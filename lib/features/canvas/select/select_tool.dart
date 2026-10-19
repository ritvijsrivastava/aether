import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/model/models.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';
import '../ink/ink_layer.dart';
import '../input/tool_gestures.dart';
import '../marks/mark_layers.dart';
import '../notes/notes_layer.dart';
import 'mark_hit.dart';
import 'selection.dart';

/// Where finished selection edits go.
abstract interface class SelectSink {
  /// Saves the new state of marks that were moved, as one undo step.
  void commitMove(List<Mark> finals);
}

/// The loop or rectangle being drawn.
class LiveLasso extends ChangeNotifier {
  bool active = false;
  bool marquee = false;

  /// World space. A loop's points, or a rectangle's two corners.
  final List<Offset> points = [];

  void begin(Offset p, {required bool rectangle}) {
    active = true;
    marquee = rectangle;
    points
      ..clear()
      ..add(p);
    notifyListeners();
  }

  void add(Offset p) {
    if (marquee) {
      if (points.length > 1) points.removeLast();
      points.add(p);
    } else {
      points.add(p);
    }
    notifyListeners();
  }

  void end() {
    active = false;
    points.clear();
    notifyListeners();
  }

  Rect? get rect => marquee && points.length == 2
      ? Rect.fromPoints(points[0], points[1])
      : null;
}

/// The Select tool (SPEC 8).
///
/// - Draw a loop round marks to select them (half of a mark inside counts);
///   Shift-drag with a mouse draws a rectangle instead.
/// - Tap a mark to select just it; tap empty canvas to clear.
/// - Drag inside the dashed outline to move the selection (ink and notes; a
///   highlight belongs to its text and stays).
class SelectToolController implements ToolHandler {
  SelectToolController({
    required this.view,
    required this.scene,
    required this.selection,
    required this.live,
    required this.ink,
    required this.highlights,
    required this.notes,
    required this.shift,
    this.sink,
  });

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final SelectionState selection;
  final LiveLasso live;
  final InkLayer ink;
  final HighlightLayer highlights;
  final NotesLayer notes;

  /// Whether Shift is held (a rectangle instead of a loop).
  final bool Function() shift;
  SelectSink? sink;

  /// Movement beyond this many dp is a drag, not a tap.
  static const double tapSlopPx = 8;

  /// How far outside the dashed outline a press still grabs the selection.
  static const double grabPx = 8;

  MarkHitTester get _hit => MarkHitTester(
    scene: scene.value,
    ink: ink,
    highlights: highlights,
    notes: notes,
  );

  _Mode _mode = _Mode.idle;
  Offset _downScreen = Offset.zero;
  Offset _downWorld = Offset.zero;
  bool _moved = false;

  // For a move: the marks as they were, to restore on cancel and to measure
  // the shift from.
  final Map<String, Ink> _inkBefore = {};
  final Map<String, Note> _notesBefore = {};
  Offset _applied = Offset.zero;

  bool get isActive => _mode != _Mode.idle;

  @override
  void start(ToolPoint p) {
    _downScreen = p.position;
    _downWorld = view.value.screenToWorld(p.position);
    _moved = false;
    _applied = Offset.zero;
    if (!selection.isEmpty &&
        _grabsSelection(_downWorld) &&
        _movable.isNotEmpty) {
      _mode = _Mode.move;
      for (final r in _movable) {
        if (r.kind == MarkKind.ink) _inkBefore[r.id] = ink.byId(r.id)!;
        if (r.kind == MarkKind.note) _notesBefore[r.id] = notes.byId(r.id)!;
      }
      return;
    }
    _mode = _Mode.loop;
  }

  List<MarkRef> get _movable => [
    for (final r in selection.refs)
      if (r.kind != MarkKind.highlight &&
          (r.kind == MarkKind.ink
              ? ink.byId(r.id) != null
              : notes.byId(r.id) != null))
        r,
  ];

  bool _grabsSelection(Offset world) {
    final b = _hit.unionBounds(selection.refs);
    return b != null && b.inflate(grabPx / view.value.zoom).contains(world);
  }

  @override
  void move(ToolPoint p) {
    if (_mode == _Mode.idle) return;
    if (!_moved) {
      if ((p.position - _downScreen).distance <= tapSlopPx) return;
      _moved = true;
      if (_mode == _Mode.loop) live.begin(_downWorld, rectangle: shift());
    }
    final world = view.value.screenToWorld(p.position);
    if (_mode == _Mode.loop) {
      live.add(world);
    } else {
      _applyShift(world - _downWorld);
    }
  }

  void _applyShift(Offset d) {
    if (d == _applied) return;
    _applied = d;
    // Ink and notes are in their page's space, which is world space shifted,
    // so the same shift applies to all of them.
    for (final s in _inkBefore.values) {
      ink.add(s.translated(d.dx, d.dy));
    }
    for (final n in _notesBefore.values) {
      notes.update(n.copyWith(x: n.x + d.dx, y: n.y + d.dy));
    }
  }

  @override
  void end(ToolPoint p) {
    final mode = _mode;
    if (mode == _Mode.idle) return;
    final world = view.value.screenToWorld(p.position);
    switch (mode) {
      case _Mode.move:
        if (_moved) {
          _applyShift(world - _downWorld);
          final finals = <Mark>[
            for (final id in _inkBefore.keys) ink.byId(id)!,
            for (final id in _notesBefore.keys) notes.byId(id)!,
          ];
          if (_applied != Offset.zero && finals.isNotEmpty) {
            sink?.commitMove(finals);
          }
        } else {
          _tap(world);
        }
      case _Mode.loop:
        if (_moved) {
          final hit = _hit;
          final marks = live.marquee
              ? hit.inRect(Rect.fromPoints(_downWorld, world))
              : hit.inLoop([
                  for (final q in live.points) ...[q.dx, q.dy],
                ]);
          selection.set(marks);
        } else {
          _tap(world);
        }
      case _Mode.idle:
        break;
    }
    _reset();
  }

  void _tap(Offset world) {
    final ref = _hit.markAt(world, view.value.zoom);
    selection.set(ref == null ? const [] : [ref]);
  }

  @override
  void cancel() {
    if (_mode == _Mode.move) {
      for (final s in _inkBefore.values) {
        ink.add(s);
      }
      for (final n in _notesBefore.values) {
        notes.update(n);
      }
    }
    _reset();
  }

  void _reset() {
    _mode = _Mode.idle;
    _moved = false;
    _inkBefore.clear();
    _notesBefore.clear();
    _applied = Offset.zero;
    if (live.active) live.end();
  }
}

enum _Mode { idle, loop, move }
