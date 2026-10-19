import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/geometry/box.dart';
import '../model/ink_codec.dart';

/// Pure geometry for ink strokes: simplifying a stroke for storage, and
/// turning its samples into the outline of a pressure-width ribbon to fill.
///
/// Samples are `x, y, pressure` triplets (see [InkCodec]) in page points.
abstract final class InkGeometry {
  static const int _s = InkCodec.stride;

  /// Drops samples that lie within [tolerance] of the line through their
  /// neighbours (Ramer-Douglas-Peucker on x, y), keeping the first and last
  /// and each kept sample's pressure. A stroke of 2 samples or fewer is
  /// returned as it is.
  static Float32List simplify(Float32List samples, double tolerance) {
    final n = samples.length ~/ _s;
    if (n <= 2 || tolerance <= 0) return samples;
    final keep = List<bool>.filled(n, false);
    keep[0] = keep[n - 1] = true;
    final stack = <(int, int)>[(0, n - 1)];
    while (stack.isNotEmpty) {
      final (a, b) = stack.removeLast();
      var worst = -1.0;
      var at = -1;
      for (var i = a + 1; i < b; i++) {
        final d = _segDistance(
          samples[i * _s],
          samples[i * _s + 1],
          samples[a * _s],
          samples[a * _s + 1],
          samples[b * _s],
          samples[b * _s + 1],
        );
        if (d > worst) {
          worst = d;
          at = i;
        }
      }
      if (worst > tolerance && at > 0) {
        keep[at] = true;
        stack.add((a, at));
        stack.add((at, b));
      }
    }
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      if (keep[i]) {
        out
          ..add(samples[i * _s])
          ..add(samples[i * _s + 1])
          ..add(samples[i * _s + 2]);
      }
    }
    return Float32List.fromList(out);
  }

  /// Distance from point (px, py) to the segment (ax, ay)-(bx, by).
  static double _segDistance(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) {
      return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  /// The box of all samples, grown by half of [width] each side.
  static Box bounds(Float32List s, double width) {
    if (s.isEmpty) return const Box(0, 0, 0, 0);
    var x0 = s[0], y0 = s[1], x1 = x0, y1 = y0;
    for (var i = 0; i < s.length; i += _s) {
      final x = s[i], y = s[i + 1];
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
    final pad = width / 2;
    return Box(x0 - pad, y0 - pad, x1 + pad, y1 + pad);
  }

  /// The smoothed centre line as `x, y, width` triplets.
  ///
  /// Quadratic midpoint smoothing: the line runs from the middle of one
  /// segment to the middle of the next with the sample between them as the
  /// control point, so corners round off and the line stays near the pen.
  /// [widthOf] maps a pressure to a line width.
  static List<double> centerline(
    Float32List samples,
    double Function(double pressure) widthOf,
  ) {
    // Drop repeated points: they carry no direction.
    final px = <double>[], py = <double>[], pw = <double>[];
    for (var i = 0; i < samples.length; i += _s) {
      final x = samples[i].toDouble(), y = samples[i + 1].toDouble();
      if (px.isNotEmpty &&
          (x - px.last).abs() < 1e-4 &&
          (y - py.last).abs() < 1e-4) {
        continue;
      }
      px.add(x);
      py.add(y);
      pw.add(widthOf(samples[i + 2].toDouble()));
    }
    final n = px.length;
    final out = <double>[];
    if (n == 0) return out;
    if (n <= 2) {
      for (var i = 0; i < n; i++) {
        out
          ..add(px[i])
          ..add(py[i])
          ..add(pw[i]);
      }
      return out;
    }
    out
      ..add(px[0])
      ..add(py[0])
      ..add(pw[0]);
    for (var i = 1; i < n - 1; i++) {
      final sx = i == 1 ? px[0] : (px[i - 1] + px[i]) / 2;
      final sy = i == 1 ? py[0] : (py[i - 1] + py[i]) / 2;
      final sw = i == 1 ? pw[0] : (pw[i - 1] + pw[i]) / 2;
      final ex = i == n - 2 ? px[n - 1] : (px[i] + px[i + 1]) / 2;
      final ey = i == n - 2 ? py[n - 1] : (py[i] + py[i + 1]) / 2;
      final ew = i == n - 2 ? pw[n - 1] : (pw[i] + pw[i + 1]) / 2;
      final chord = math.sqrt((ex - sx) * (ex - sx) + (ey - sy) * (ey - sy));
      final steps = (chord / 1.5).ceil().clamp(1, 8);
      for (var k = 1; k <= steps; k++) {
        final t = k / steps, u = 1 - t;
        out
          ..add(u * u * sx + 2 * u * t * px[i] + t * t * ex)
          ..add(u * u * sy + 2 * u * t * py[i] + t * t * ey)
          ..add(u * u * sw + 2 * u * t * pw[i] + t * t * ew);
      }
    }
    return out;
  }

  /// The closed outline (`x, y` pairs) of a ribbon along [center] (from
  /// [centerline]) with round caps. Fill it with the non-zero rule. A single
  /// point is a disc.
  static List<double> outline(List<double> center) {
    final m = center.length ~/ 3;
    final out = <double>[];
    if (m == 0) return out;
    const capSteps = 6;
    if (m == 1) {
      final r = center[2] / 2;
      for (var k = 0; k < capSteps * 2; k++) {
        final a = k * math.pi / capSteps;
        out
          ..add(center[0] + r * math.cos(a))
          ..add(center[1] + r * math.sin(a));
      }
      return out;
    }
    final lx = List<double>.filled(m, 0), ly = List<double>.filled(m, 0);
    final rx = List<double>.filled(m, 0), ry = List<double>.filled(m, 0);
    final nxs = List<double>.filled(m, 0), nys = List<double>.filled(m, 0);
    for (var i = 0; i < m; i++) {
      final a = i == 0 ? 0 : i - 1, b = i == m - 1 ? m - 1 : i + 1;
      var tx = center[b * 3] - center[a * 3];
      var ty = center[b * 3 + 1] - center[a * 3 + 1];
      final len = math.sqrt(tx * tx + ty * ty);
      if (len == 0) {
        tx = 1;
        ty = 0;
      } else {
        tx /= len;
        ty /= len;
      }
      final nx = -ty, ny = tx;
      nxs[i] = nx;
      nys[i] = ny;
      final r = center[i * 3 + 2] / 2;
      lx[i] = center[i * 3] + nx * r;
      ly[i] = center[i * 3 + 1] + ny * r;
      rx[i] = center[i * 3] - nx * r;
      ry[i] = center[i * 3 + 1] - ny * r;
    }
    for (var i = 0; i < m; i++) {
      out
        ..add(lx[i])
        ..add(ly[i]);
    }
    // End cap: from the left edge, around the front, to the right edge.
    final e = m - 1;
    final er = center[e * 3 + 2] / 2;
    final ea = math.atan2(nys[e], nxs[e]);
    for (var k = 1; k < capSteps; k++) {
      final a = ea - k * math.pi / capSteps;
      out
        ..add(center[e * 3] + er * math.cos(a))
        ..add(center[e * 3 + 1] + er * math.sin(a));
    }
    for (var i = m - 1; i >= 0; i--) {
      out
        ..add(rx[i])
        ..add(ry[i]);
    }
    // Start cap: from the right edge, around the back, to the left edge.
    final sr = center[2] / 2;
    final sa = math.atan2(nys[0], nxs[0]);
    for (var k = 1; k < capSteps; k++) {
      final a = sa + math.pi - k * math.pi / capSteps;
      out
        ..add(center[0] + sr * math.cos(a))
        ..add(center[1] + sr * math.sin(a));
    }
    return out;
  }

  /// One to two points ahead of the pen, from its recent speed, to hide about
  /// a frame of latency. [recent] is the last few samples as `x, y, ms`
  /// triplets (oldest first). Returns `x, y` pairs, or nothing if the pen is
  /// still, too slow, or the samples are too sparse to trust.
  static List<double> predict(List<double> recent, {double horizonMs = 16}) {
    final n = recent.length ~/ 3;
    if (n < 3) return const [];
    final a = n - 3, c = n - 1;
    final dt = recent[c * 3 + 2] - recent[a * 3 + 2];
    if (dt <= 0 || dt > 60) return const [];
    final vx = (recent[c * 3] - recent[a * 3]) / dt;
    final vy = (recent[c * 3 + 1] - recent[a * 3 + 1]) / dt;
    final speed = math.sqrt(vx * vx + vy * vy);
    if (speed < 0.02) return const []; // points per ms: a standing pen
    // Never run further than the pen moved in the same time lately, and damp
    // the far point: a turn would otherwise overshoot.
    final x = recent[c * 3], y = recent[c * 3 + 1];
    return [
      x + vx * horizonMs * 0.5,
      y + vy * horizonMs * 0.5,
      x + vx * horizonMs * 0.9,
      y + vy * horizonMs * 0.9,
    ];
  }

  /// Whether a circle of radius [r] at ([cx], [cy]) touches a stroke drawn
  /// [width] wide: its centre line comes within `r + width / 2` of the centre.
  static bool touches(
    Float32List s,
    double width,
    double cx,
    double cy,
    double r,
  ) {
    final n = s.length ~/ _s;
    if (n == 0) return false;
    final reach = r + width / 2;
    if (n == 1) {
      final dx = s[0] - cx, dy = s[1] - cy;
      return dx * dx + dy * dy <= reach * reach;
    }
    for (var i = 0; i + 1 < n; i++) {
      final d = _segDistance(
        cx,
        cy,
        s[i * _s],
        s[i * _s + 1],
        s[(i + 1) * _s],
        s[(i + 1) * _s + 1],
      );
      if (d <= reach) return true;
    }
    return false;
  }

  /// What is left of a stroke after a circle of radius [r] at ([cx], [cy])
  /// (grown by half the stroke [width]) is wiped across it: zero, one or two
  /// or more pieces, cut exactly at the circle's edge (pressure interpolated),
  /// each with at least two points. Returns `[s]` itself, unchanged, if the
  /// circle does not touch it.
  static List<Float32List> eraseSplit(
    Float32List s,
    double width,
    double cx,
    double cy,
    double r,
  ) {
    final n = s.length ~/ _s;
    final reach = r + width / 2;
    if (!touches(s, width, cx, cy, r)) return [s];
    if (n == 1) return const [];

    final pieces = <List<double>>[];
    var cur = <double>[];

    bool inside(int i) {
      final dx = s[i * _s] - cx, dy = s[i * _s + 1] - cy;
      return dx * dx + dy * dy <= reach * reach;
    }

    void add(List<double> into, double x, double y, double p) => into
      ..add(x)
      ..add(y)
      ..add(p);

    if (!inside(0)) add(cur, s[0], s[1], s[2]);
    for (var i = 0; i + 1 < n; i++) {
      final ax = s[i * _s].toDouble(), ay = s[i * _s + 1].toDouble();
      final ap = s[i * _s + 2].toDouble();
      final bx = s[(i + 1) * _s].toDouble(),
          by = s[(i + 1) * _s + 1].toDouble();
      final bp = s[(i + 1) * _s + 2].toDouble();
      final dx = bx - ax, dy = by - ay;
      // Solve |A + t (B - A) - C|^2 = reach^2 for t.
      final fx = ax - cx, fy = ay - cy;
      final qa = dx * dx + dy * dy;
      final qb = 2 * (fx * dx + fy * dy);
      final qc = fx * fx + fy * fy - reach * reach;
      double? t0, t1;
      if (qa > 0) {
        final disc = qb * qb - 4 * qa * qc;
        if (disc >= 0) {
          final sq = math.sqrt(disc);
          final lo = (-qb - sq) / (2 * qa), hi = (-qb + sq) / (2 * qa);
          if (hi >= 0 && lo <= 1) {
            t0 = lo.clamp(0.0, 1.0);
            t1 = hi.clamp(0.0, 1.0);
          }
        }
      }
      if (t0 == null || t1 == null) {
        add(cur, bx, by, bp); // wholly outside
        continue;
      }
      if (t0 > 0) {
        add(cur, ax + dx * t0, ay + dy * t0, ap + (bp - ap) * t0);
        pieces.add(cur);
        cur = <double>[];
      } else if (cur.isNotEmpty) {
        // A was inside but a piece is open: cannot happen, close it anyway.
        pieces.add(cur);
        cur = <double>[];
      }
      if (t1 < 1) {
        add(cur, ax + dx * t1, ay + dy * t1, ap + (bp - ap) * t1);
        add(cur, bx, by, bp);
      }
    }
    if (cur.isNotEmpty) pieces.add(cur);

    final out = <Float32List>[];
    for (final p in pieces) {
      if (p.length ~/ _s >= 2 && _length(p) > 0.05) {
        out.add(Float32List.fromList(p));
      }
    }
    return out;
  }

  static double _length(List<double> p) {
    var len = 0.0;
    for (var i = _s; i < p.length; i += _s) {
      final dx = p[i] - p[i - _s], dy = p[i + 1] - p[i - _s + 1];
      len += math.sqrt(dx * dx + dy * dy);
    }
    return len;
  }
}
