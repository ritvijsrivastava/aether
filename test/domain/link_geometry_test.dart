import 'dart:math' as math;

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/marks/link_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const note = Box(100, 100, 300, 220); // 200 x 120, centre (200, 160)

  group('edgeToward', () {
    test('leaves through the side the target is on', () {
      expect(
        LinkGeometry.edgeToward(note, const Offset(1000, 160)),
        const Offset(300, 160),
      );
      expect(
        LinkGeometry.edgeToward(note, const Offset(-500, 160)),
        const Offset(100, 160),
      );
      expect(
        LinkGeometry.edgeToward(note, const Offset(200, 900)),
        const Offset(200, 220),
      );
      expect(
        LinkGeometry.edgeToward(note, const Offset(200, -900)),
        const Offset(200, 100),
      );
    });

    test('a diagonal target meets the nearer edge', () {
      // 45 degrees: the box is wider than tall, so the top/bottom edge is hit.
      final p = LinkGeometry.edgeToward(note, const Offset(500, 460));
      expect(p.dy, closeTo(220, 1e-9));
      expect(p.dx, closeTo(260, 1e-9));
    });

    test('is always on the boundary of the rectangle', () {
      final rnd = math.Random(2);
      for (var i = 0; i < 200; i++) {
        final t = Offset(
          rnd.nextDouble() * 2000 - 800,
          rnd.nextDouble() * 2000 - 800,
        );
        final p = LinkGeometry.edgeToward(note, t);
        final onX = (p.dx - 100).abs() < 1e-6 || (p.dx - 300).abs() < 1e-6;
        final onY = (p.dy - 100).abs() < 1e-6 || (p.dy - 220).abs() < 1e-6;
        expect(onX || onY, isTrue);
        expect(p.dx, inInclusiveRange(100 - 1e-6, 300 + 1e-6));
        expect(p.dy, inInclusiveRange(100 - 1e-6, 220 + 1e-6));
      }
    });

    test('a target at the centre gives the centre', () {
      expect(
        LinkGeometry.edgeToward(note, const Offset(200, 160)),
        const Offset(200, 160),
      );
    });
  });

  group('onHighlight', () {
    const rects = [Box(100, 500, 400, 510), Box(100, 520, 250, 530)];

    test('picks the nearest line and the nearest point along it', () {
      expect(
        LinkGeometry.onHighlight(rects, const Offset(200, 300)),
        const Offset(200, 505),
      );
      expect(
        LinkGeometry.onHighlight(rects, const Offset(900, 560)),
        const Offset(400, 505),
      );
      expect(
        LinkGeometry.onHighlight(rects, const Offset(0, 505)),
        const Offset(100, 505),
      );
    });
  });

  group('curve', () {
    const a = Offset(0, 0), b = Offset(100, 0);

    test('bows to the same side whichever way it is asked', () {
      final c1 = LinkGeometry.control(a, b);
      expect(c1.dx, closeTo(50, 1e-9));
      expect(c1.dy.abs(), closeTo(20, 1e-9));
      final c2 = LinkGeometry.control(b, a);
      expect(
        c2.dy,
        closeTo(-c1.dy, 1e-9),
        reason: 'opposite direction, opposite side',
      );
    });

    test('passes through its ends and the control shapes the middle', () {
      final c = LinkGeometry.control(a, b);
      expect(LinkGeometry.at(a, c, b, 0), a);
      expect(LinkGeometry.at(a, c, b, 1), b);
      final m = LinkGeometry.at(a, c, b, 0.5);
      expect(m.dy.abs(), closeTo(10, 1e-9)); // half the control offset
    });

    test('a zero-length link does not blow up', () {
      expect(LinkGeometry.control(a, a), a);
    });
  });

  group('distanceToCurve', () {
    const a = Offset(0, 0), b = Offset(200, 0);

    test('is near zero on the line and grows away from it', () {
      final c = LinkGeometry.control(a, b);
      final onIt = LinkGeometry.at(a, c, b, 0.3);
      expect(LinkGeometry.distanceToCurve(onIt, a, c, b), lessThan(0.5));
      expect(
        LinkGeometry.distanceToCurve(onIt + const Offset(0, 30), a, c, b),
        greaterThan(20),
      );
    });

    test('measures to the ends past them', () {
      final c = LinkGeometry.control(a, b);
      expect(
        LinkGeometry.distanceToCurve(const Offset(-50, 0), a, c, b),
        closeTo(50, 1),
      );
    });
  });

  test('distanceToBox is zero inside and measured to the edge outside', () {
    expect(LinkGeometry.distanceToBox(note, const Offset(150, 150)), 0);
    expect(LinkGeometry.distanceToBox(note, const Offset(350, 160)), 50);
    expect(LinkGeometry.distanceToBox(note, const Offset(303, 224)), 5);
  });
}
