import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/model/models.dart';
import '../engine/view_state.dart';
import '../ink/ink_layer.dart';
import '../input/tool_gestures.dart';
import 'ink_hit.dart';
import 'selection.dart';

/// Where finished selection edits go.
abstract interface class SelectSink {
  /// Saves the new state of marks that were moved, as one undo step.
  void commitMove(List<Mark> finals);

  /// A new id for a piece cut from a stroke.
  String newId();

  /// Strokes cut by the selection's edge are replaced by their pieces: one
  /// undo step.
  void commitCut({required Set<String> deleted, required List<Ink> created});
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
/// - Drag inside the dashed outline to move the selection (ink).
class SelectToolController implements ToolHandler {
  SelectToolController({
    required this.view,
    required this.selection,
    required this.live,
    required this.ink,
    required this.shift,
    this.sink,
  });

  final ValueListenable<ViewState> view;
  final SelectionState selection;
  final LiveLasso live;
  final InkLayer ink;

  /// Whether Shift is held (a rectangle instead of a loop).
  final bool Function() shift;
  SelectSink? sink;

  /// Movement beyond this many dp is a drag, not a tap.
  static const double tapSlopPx = 8;

  /// How far outside the dashed outline a press still grabs the selection.
  static const double grabPx = 8;

  InkHitTester get _hit => InkHitTester(ink: ink);

  _Mode _mode = _Mode.idle;
  Offset _downScreen = Offset.zero;
  Offset _downWorld = Offset.zero;
  bool _moved = false;

  // For a move: the marks as they were, to restore on cancel and to measure
  // the shift from.
  final Map<String, Ink> _inkBefore = {};
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
        _inkBefore[r.id] = ink.byId(r.id)!;
      }
      return;
    }
    _mode = _Mode.loop;
  }

  List<MarkRef> get _movable => [
    for (final r in selection.refs)
      if (r.kind == MarkKind.ink && ink.byId(r.id) != null) r,
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
    for (final s in _inkBefore.values) {
      ink.add(s.translated(d.dx, d.dy));
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
          final picked = live.marquee
              ? hit.cutRect(Rect.fromPoints(_downWorld, world))
              : hit.cutLoop(live.points);
          _pick(picked);
        } else {
          _tap(world);
        }
      case _Mode.idle:
        break;
    }
    _reset();
  }

  /// Selects what the region picked up. A stroke it only passes through is
  /// cut at the edge, so just the part inside is selected and can be moved;
  /// the rest stays where it was.
  void _pick(RegionCut picked) {
    final refs = <MarkRef>[
      for (final s in picked.whole) MarkRef(MarkKind.ink, s.id),
    ];
    if (picked.cuts.isNotEmpty && sink != null) {
      final deleted = <String>{};
      final created = <Ink>[];
      Ink piece(Ink from, Float32List samples) => Ink(
        id: sink!.newId(),
        docId: from.docId,
        samples: samples,
        width: from.width,
        color: from.color,
      );
      for (final c in picked.cuts) {
        ink.remove(c.original.id);
        deleted.add(c.original.id);
        for (final out in c.outside) {
          final p = piece(c.original, out);
          ink.add(p);
          created.add(p);
        }
        for (final inn in c.inside) {
          final p = piece(c.original, inn);
          ink.add(p);
          created.add(p);
          refs.add(MarkRef(MarkKind.ink, p.id));
        }
      }
      sink!.commitCut(deleted: deleted, created: created);
    }
    selection.set(refs);
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
    }
    _reset();
  }

  void _reset() {
    _mode = _Mode.idle;
    _moved = false;
    _inkBefore.clear();
    _applied = Offset.zero;
    if (live.active) live.end();
  }
}

enum _Mode { idle, loop, move }
