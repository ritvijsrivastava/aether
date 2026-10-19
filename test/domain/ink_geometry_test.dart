import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aether/domain/ink/ink_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List stroke(List<(double, double, double)> pts) => Float32List.fromList([
  for (final (x, y, p) in pts) ...[x, y, p],
]);

double w(double pressure) => 4 * pressure;

void main() {
  group('simplify', () {
    test('a straight line keeps only its ends', () {
      final s = stroke([for (var i = 0; i <= 50; i++) (i * 2.0, i * 1.0, 0.5)]);
      final out = InkGeometry.simplify(s, 0.15);
      expect(out.length, 6);
      expect([out[0], out[1], out[3], out[4]], [0, 0, 100, 50]);
    });

    test('keeps the corner of an L, drops the points along the arms', () {
      final s = stroke([
        for (var i = 0; i <= 10; i++) (i * 10.0, 0, 0.5),
        for (var i = 1; i <= 10; i++) (100, i * 10.0, 0.5),
      ]);
      final out = InkGeometry.simplify(s, 0.5);
      expect(out.length ~/ 3, 3);
      expect([out[3], out[4]], [100, 0]);
    });

    test('keeps the pressure of the samples it keeps', () {
      final s = stroke([(0, 0, 0.1), (50, 0, 0.7), (100, 40, 0.3)]);
      final out = InkGeometry.simplify(s, 0.1);
      expect(
        [out[2], out[5], out[8]],
        [closeTo(0.1, 1e-6), closeTo(0.7, 1e-6), closeTo(0.3, 1e-6)],
      );
    });

    test('a wobble under the tolerance goes, over it stays', () {
      final s = stroke([(0, 0, 1), (50, 0.1, 1), (100, 0, 1)]);
      expect(InkGeometry.simplify(s, 0.15).length ~/ 3, 2);
      expect(InkGeometry.simplify(s, 0.05).length ~/ 3, 3);
    });

    test('short strokes and a zero tolerance are returned as they are', () {
      final dot = stroke([(5, 5, 1)]);
      final seg = stroke([(0, 0, 1), (9, 9, 1)]);
      expect(InkGeometry.simplify(dot, 1), same(dot));
      expect(InkGeometry.simplify(seg, 1), same(seg));
      final s = stroke([(0, 0, 1), (5, 1, 1), (10, 0, 1)]);
      expect(InkGeometry.simplify(s, 0), same(s));
    });

    test('a 20,000-point scribble simplifies quickly and never grows', () {
      final rnd = math.Random(1);
      final s = stroke([
        for (var i = 0; i < 20000; i++)
          (i * 0.05 + rnd.nextDouble() * 0.05, math.sin(i / 40) * 20, 0.5),
      ]);
      final sw = Stopwatch()..start();
      final out = InkGeometry.simplify(s, 0.15);
      expect(out.length, lessThan(s.length));
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('stays within the tolerance of the original path', () {
      final s = stroke([
        for (var i = 0; i < 400; i++) (i * 1.0, math.sin(i / 25) * 30, 0.5),
      ]);
      const tol = 0.3;
      final out = InkGeometry.simplify(s, tol);
      // Every original sample is within tol of the simplified polyline.
      for (var i = 0; i < s.length; i += 3) {
        var best = double.infinity;
        for (var j = 0; j + 5 < out.length; j += 3) {
          final d = _dist(
            s[i],
            s[i + 1],
            out[j],
            out[j + 1],
            out[j + 3],
            out[j + 4],
          );
          if (d < best) best = d;
        }
        expect(best, lessThanOrEqualTo(tol + 1e-3));
      }
    });
  });

  group('bounds', () {
    test('cover every sample plus half the width', () {
      final b = InkGeometry.bounds(
        stroke([(10, 20, 1), (40, 5, 1), (25, 60, 1)]),
        6,
      );
      expect([b.x0, b.y0, b.x1, b.y1], [7, 2, 43, 63]);
    });

    test('an empty stroke has empty bounds', () {
      expect(InkGeometry.bounds(Float32List(0), 4).width, 0);
    });
  });

  group('centerline', () {
    test('keeps the ends and rounds off a corner', () {
      final c = InkGeometry.centerline(
        stroke([(0, 0, 1), (50, 0, 1), (50, 50, 1)]),
        w,
      );
      expect([c.first, c[1]], [0, 0]);
      expect([c[c.length - 3], c[c.length - 2]], [50, 50]);
      // The corner point (50, 0) is not on the smoothed line.
      var nearCorner = double.infinity;
      for (var i = 0; i < c.length; i += 3) {
        nearCorner = math.min(
          nearCorner,
          math.sqrt(math.pow(c[i] - 50, 2) + math.pow(c[i + 1], 2)),
        );
      }
      expect(nearCorner, greaterThan(1));
    });

    test('carries the width from pressure and interpolates it', () {
      final c = InkGeometry.centerline(
        stroke([(0, 0, 0.25), (40, 0, 0.5), (80, 0, 1.0)]),
        w,
      );
      expect(c[2], closeTo(1.0, 1e-6)); // 4 * 0.25
      expect(c[c.length - 1], closeTo(4.0, 1e-6));
      for (var i = 5; i < c.length; i += 3) {
        expect(c[i], greaterThanOrEqualTo(c[i - 3] - 1e-6), reason: 'widens');
      }
    });

    test('repeated points are dropped, not turned into NaN', () {
      final c = InkGeometry.centerline(
        stroke([(5, 5, 1), (5, 5, 1), (5, 5, 1), (9, 9, 1), (9, 9, 1)]),
        w,
      );
      expect(c.every((v) => v.isFinite), isTrue);
      expect(c.length ~/ 3, 2);
    });

    test('empty, one and two points', () {
      expect(InkGeometry.centerline(Float32List(0), w), isEmpty);
      expect(InkGeometry.centerline(stroke([(1, 2, 1)]), w).length, 3);
      expect(
        InkGeometry.centerline(stroke([(1, 2, 1), (3, 4, 1)]), w).length,
        6,
      );
    });
  });

  group('outline', () {
    List<double> ribbon(List<(double, double, double)> pts) =>
        InkGeometry.outline(InkGeometry.centerline(stroke(pts), w));

    (double, double, double, double) box(List<double> o) {
      var x0 = double.infinity, y0 = double.infinity;
      var x1 = -double.infinity, y1 = -double.infinity;
      for (var i = 0; i < o.length; i += 2) {
        x0 = math.min(x0, o[i]);
        x1 = math.max(x1, o[i]);
        y0 = math.min(y0, o[i + 1]);
        y1 = math.max(y1, o[i + 1]);
      }
      return (x0, y0, x1, y1);
    }

    test('a horizontal line of width 4 is 4 tall and has round caps', () {
      final (x0, y0, x1, y1) = box(ribbon([(10, 50, 1), (110, 50, 1)]));
      expect(y1 - y0, closeTo(4, 1e-6));
      expect(
        x0,
        closeTo(8, 1e-6),
        reason: 'cap reaches width/2 before the start',
      );
      expect(x1, closeTo(112, 1e-6));
    });

    test('a single point is a disc of the stroke width', () {
      final o = ribbon([(30, 30, 1)]);
      final (x0, y0, x1, y1) = box(o);
      expect(x1 - x0, closeTo(4, 1e-6));
      expect(y1 - y0, closeTo(4, 1e-6));
      for (var i = 0; i < o.length; i += 2) {
        expect(
          math.sqrt(math.pow(o[i] - 30, 2) + math.pow(o[i + 1] - 30, 2)),
          closeTo(2, 1e-6),
        );
      }
    });

    test('pressure makes the ribbon wider where the pen pressed harder', () {
      final o = ribbon([
        for (var i = 0; i <= 10; i++) (i * 10.0, 0, 0.25 + 0.075 * i),
      ]);
      // Compare thickness near x = 10 and x = 90.
      double thick(double x) {
        var lo = double.infinity, hi = -double.infinity;
        for (var i = 0; i < o.length; i += 2) {
          if ((o[i] - x).abs() < 6) {
            lo = math.min(lo, o[i + 1]);
            hi = math.max(hi, o[i + 1]);
          }
        }
        return hi - lo;
      }

      expect(thick(90), greaterThan(thick(10) * 1.5));
    });

    test('every coordinate is finite for any input, including stalls', () {
      final rnd = math.Random(4);
      for (var run = 0; run < 50; run++) {
        final pts = [
          for (var i = 0; i < 1 + rnd.nextInt(40); i++)
            (rnd.nextInt(5) * 3.0, rnd.nextInt(5) * 3.0, rnd.nextDouble()),
        ];
        expect(ribbon(pts).every((v) => v.isFinite), isTrue);
      }
    });

    test('empty in, empty out', () {
      expect(InkGeometry.outline(const []), isEmpty);
    });
  });

  group('predict', () {
    List<double> moving(double vx, double vy, {double dt = 2}) => [
      for (var i = 0; i < 4; i++) ...[
        100 + vx * i * dt,
        50 + vy * i * dt,
        i * dt,
      ],
    ];

    test('runs ahead along the pen\'s velocity', () {
      final p = InkGeometry.predict(moving(1.0, 0.5));
      expect(p.length, 4);
      // Last sample is at (106, 53); 16 ms ahead at (1, 0.5) per ms.
      expect(p[0], closeTo(106 + 8, 1e-6));
      expect(p[1], closeTo(53 + 4, 1e-6));
      expect(p[2], greaterThan(p[0]));
    });

    test('a standing pen predicts nothing', () {
      expect(InkGeometry.predict(moving(0, 0)), isEmpty);
    });

    test('too few samples, or a long gap in time, predict nothing', () {
      expect(InkGeometry.predict([1, 1, 0, 2, 2, 2]), isEmpty);
      expect(
        InkGeometry.predict([0, 0, 0, 10, 0, 100, 20, 0, 200]),
        isEmpty,
        reason: 'samples 200 ms apart say nothing about the next 16',
      );
    });
  });
}

double _dist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  final t = l2 == 0
      ? 0.0
      : (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}
