import 'dart:ui';

import '../../../core/geometry/polygon.dart';
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
    final hits = ink.touching(null, world.dx, world.dy, r);
    return hits.isEmpty ? null : MarkRef(MarkKind.ink, hits.last.id);
  }

  Rect? boundsOf(MarkRef ref) {
    final s = ink.byId(ref.id);
    if (s == null) return null;
    final b = s.bounds;
    return Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1);
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

  /// Strokes a loop round them selects: a stroke counts when half of it or
  /// more is inside (its samples are the measure, so a long stroke counts by
  /// how much of it is inside, not by its two ends).
  List<MarkRef> inLoop(List<Offset> loop) {
    if (loop.length < 3) return const [];
    final xy = [
      for (final p in loop) ...[p.dx, p.dy],
    ];
    final out = <MarkRef>[];
    for (final s in ink.all) {
      var inside = 0, total = 0;
      for (var i = 0; i < s.pointCount; i++) {
        total++;
        if (pointInPolygon(s.samples[i * 3], s.samples[i * 3 + 1], xy)) {
          inside++;
        }
      }
      if (total > 0 && inside * 2 >= total) {
        out.add(MarkRef(MarkKind.ink, s.id));
      }
    }
    return out;
  }

  /// Strokes a rectangle selects: the same half-or-more rule on the stroke's
  /// samples.
  List<MarkRef> inRect(Rect rect) {
    final out = <MarkRef>[];
    for (final s in ink.all) {
      var inside = 0, total = 0;
      for (var i = 0; i < s.pointCount; i++) {
        total++;
        final x = s.samples[i * 3], y = s.samples[i * 3 + 1];
        if (x >= rect.left &&
            x <= rect.right &&
            y >= rect.top &&
            y <= rect.bottom) {
          inside++;
        }
      }
      if (total > 0 && inside * 2 >= total) {
        out.add(MarkRef(MarkKind.ink, s.id));
      }
    }
    return out;
  }
}
