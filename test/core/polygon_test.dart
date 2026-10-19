import 'dart:math' as math;

import 'package:aether/core/geometry/polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const square = <double>[0, 0, 10, 0, 10, 10, 0, 10];

  test('inside and outside a square', () {
    expect(pointInPolygon(5, 5, square), isTrue);
    expect(pointInPolygon(15, 5, square), isFalse);
    expect(pointInPolygon(-1, 5, square), isFalse);
    expect(pointInPolygon(5, 11, square), isFalse);
  });

  test('a concave shape leaves its notch out', () {
    // An L: the notch is the top-right quarter.
    const l = <double>[0, 0, 10, 0, 10, 5, 5, 5, 5, 10, 0, 10];
    expect(pointInPolygon(2, 8, l), isTrue);
    expect(pointInPolygon(8, 2, l), isTrue);
    expect(pointInPolygon(8, 8, l), isFalse);
  });

  test('a loop drawn either way round counts the same', () {
    final reversed = <double>[0, 10, 10, 10, 10, 0, 0, 0];
    expect(pointInPolygon(5, 5, reversed), isTrue);
    expect(pointInPolygon(50, 5, reversed), isFalse);
  });

  test('fewer than three points is nothing', () {
    expect(pointInPolygon(1, 1, const []), isFalse);
    expect(pointInPolygon(1, 1, const <double>[0, 0, 2, 2]), isFalse);
  });

  test('a freehand wobbly loop with many points', () {
    final pts = <double>[];
    for (var i = 0; i < 360; i += 5) {
      final a = i * math.pi / 180;
      final r = 50 + 5 * (i % 20 == 0 ? 1 : -1);
      pts
        ..add(100 + r * math.cos(a))
        ..add(100 + r * math.sin(a));
    }
    expect(pointInPolygon(100, 100, pts), isTrue);
    expect(pointInPolygon(100, 100 + 70, pts), isFalse);
  });
}
