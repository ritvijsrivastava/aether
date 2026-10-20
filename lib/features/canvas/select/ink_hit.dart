import 'dart:typed_data';
import 'dart:ui';

import '../../../core/geometry/polygon.dart';
import '../../../domain/ink/ink_geometry.dart';
import '../../../domain/model/models.dart';
import '../ink/ink_layer.dart';
import 'selection.dart';

export 'selection.dart' show MarkRef;

/// Finds ink by place, for tapping and lassoing. All in world space.
class InkHitTester {
  const InkHitTester({required this.ink});

  final InkLayer ink;

  /// Fingertip reach on ink, in dp.
  static const double inkReachPx = 10;

  /// The stroke under [world] when the view is at [zoom].
  MarkRef? markAt(Offset world, double zoom) {
    final r = inkReachPx / zoom;
    final hits = ink.touching(world.dx, world.dy, r);
    return hits.isEmpty ? null : MarkRef(MarkKind.ink, hits.last.id);
  }

  Rect? boundsOf(MarkRef ref) {
    final b = ink.byId(ref.id)?.bounds;
    return b == null ? null : Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1);
  }

  /// The box round all of [refs] that still exist.
  Rect? unionBounds(Iterable<MarkRef> refs) {
    Rect? out;
    for (final r in refs) {
      final b = boundsOf(r);
      if (b != null) out = out == null ? b : out.expandToInclude(b);
    }
    return out;
  }

  /// What a region picks up. A stroke wholly inside is [whole]; one that
  /// crosses the edge is cut there: its inside pieces and its outside pieces
  /// are returned in a [StrokeCut], and the caller swaps the original for them.
  RegionCut cut(bool Function(double x, double y) inside) {
    final whole = <Ink>[];
    final cuts = <StrokeCut>[];
    for (final s in ink.all) {
      final runs = InkGeometry.splitByRegion(s.samples, inside);
      final ins = [
        for (final r in runs)
          if (r.inside) r.samples,
      ];
      if (ins.isEmpty) continue;
      if (runs.length == 1) {
        whole.add(s);
      } else {
        cuts.add(
          StrokeCut(
            s,
            inside: ins,
            outside: [
              for (final r in runs)
                if (!r.inside) r.samples,
            ],
          ),
        );
      }
    }
    return RegionCut(whole, cuts);
  }

  /// [cut] for a loop (the polygon of [loop] points).
  RegionCut cutLoop(List<Offset> loop) {
    if (loop.length < 3) return const RegionCut([], []);
    final xy = [
      for (final p in loop) ...[p.dx, p.dy],
    ];
    return cut((x, y) => pointInPolygon(x, y, xy));
  }

  /// [cut] for a rectangle.
  RegionCut cutRect(Rect r) =>
      cut((x, y) => x >= r.left && x <= r.right && y >= r.top && y <= r.bottom);
}

/// One stroke the region's edge runs through.
class StrokeCut {
  const StrokeCut(this.original, {required this.inside, required this.outside});
  final Ink original;
  final List<Float32List> inside, outside;
}

/// Strokes picked up whole, and strokes cut by the region's edge.
class RegionCut {
  const RegionCut(this.whole, this.cuts);
  final List<Ink> whole;
  final List<StrokeCut> cuts;

  bool get isEmpty => whole.isEmpty && cuts.isEmpty;
}
