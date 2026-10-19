import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../core/geometry/box.dart';

/// Where a link between a note and a highlight is drawn, and how to hit it.
///
/// All in one space (world space on the canvas). A link is a gentle quadratic
/// curve from the edge of the note to the nearest line of the highlight.
abstract final class LinkGeometry {
  /// The point where a ray from the centre of [rect] toward [toward] leaves
  /// the rectangle: where a link line meets a note.
  static Offset edgeToward(Box rect, Offset toward) {
    final cx = (rect.x0 + rect.x1) / 2, cy = (rect.y0 + rect.y1) / 2;
    final dx = toward.dx - cx, dy = toward.dy - cy;
    if (dx == 0 && dy == 0) return Offset(cx, cy);
    final hw = rect.width / 2, hh = rect.height / 2;
    final sx = dx == 0 ? double.infinity : hw / dx.abs();
    final sy = dy == 0 ? double.infinity : hh / dy.abs();
    final s = math.min(sx, sy);
    return Offset(cx + dx * s, cy + dy * s);
  }

  /// The anchor on the line rect of a highlight nearest to [from]: level with
  /// the middle of the line, as close to [from] horizontally as the line
  /// reaches.
  static Offset onHighlight(List<Box> rects, Offset from) {
    Box? best;
    var bestD = double.infinity;
    for (final r in rects) {
      final d = distanceToBox(r, from);
      if (d < bestD) {
        bestD = d;
        best = r;
      }
    }
    final r = best ?? rects.first;
    return Offset(from.dx.clamp(r.x0, r.x1), (r.y0 + r.y1) / 2);
  }

  /// Distance from [p] to the rectangle (0 inside).
  static double distanceToBox(Box r, Offset p) {
    final dx = p.dx < r.x0 ? r.x0 - p.dx : (p.dx > r.x1 ? p.dx - r.x1 : 0.0);
    final dy = p.dy < r.y0 ? r.y0 - p.dy : (p.dy > r.y1 ? p.dy - r.y1 : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// The control point that bows the line [a]-[b] to one side.
  static Offset control(Offset a, Offset b) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final d = b - a;
    final len = d.distance;
    if (len == 0) return mid;
    // Perpendicular, a fifth of the length, always to the same side of the
    // direction of travel so a link keeps its shape as ends move.
    return Offset(
      mid.dx - d.dy / len * len * 0.2,
      mid.dy + d.dx / len * len * 0.2,
    );
  }

  /// Point on the quadratic [a], [c], [b] at [t].
  static Offset at(Offset a, Offset c, Offset b, double t) {
    final u = 1 - t;
    return Offset(
      u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx,
      u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy,
    );
  }

  /// How far [p] is from the curve, by walking it in short steps.
  static double distanceToCurve(Offset p, Offset a, Offset c, Offset b) {
    var best = double.infinity;
    Offset prev = a;
    const steps = 24;
    for (var i = 1; i <= steps; i++) {
      final q = at(a, c, b, i / steps);
      best = math.min(best, _segDistance(p, prev, q));
      prev = q;
    }
    return best;
  }

  static double _segDistance(Offset p, Offset a, Offset b) {
    final d = b - a;
    final l2 = d.dx * d.dx + d.dy * d.dy;
    if (l2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / l2).clamp(
      0.0,
      1.0,
    );
    return (p - Offset(a.dx + d.dx * t, a.dy + d.dy * t)).distance;
  }
}
