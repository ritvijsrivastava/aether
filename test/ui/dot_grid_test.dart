import 'dart:ui';

import 'package:aether/ui/widgets/dot_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const big = Size(2560, 1600);

  test('dots sit on a regular lattice that moves with the offset', () {
    final g = gridPoints(
      const Size(200, 200),
      offset: const Offset(10, 5),
      zoom: 1,
    );
    expect(g.step, 32);
    // Every x is 10 mod 32 and every y is 5 mod 32.
    for (var i = 0; i < g.count; i++) {
      expect((g.points[i * 2] - 10) % 32, closeTo(0, 1e-4));
      expect((g.points[i * 2 + 1] - 5) % 32, closeTo(0, 1e-4));
    }
    expect(g.points[0], 10);
    expect(g.points[1], 5);
  });

  test('negative offsets still produce an in-view lattice', () {
    final g = gridPoints(
      const Size(200, 200),
      offset: const Offset(-75, -310),
      zoom: 1,
    );
    for (var i = 0; i < g.count; i++) {
      final x = g.points[i * 2], y = g.points[i * 2 + 1];
      expect(x >= 0 && x <= 200 && y >= 0 && y <= 200, isTrue);
    }
    expect(g.count, greaterThan(20));
  });

  test('the grid scales with zoom', () {
    expect(gridPoints(big, offset: Offset.zero, zoom: 2).step, 64);
    expect(gridPoints(big, offset: Offset.zero, zoom: 0.5).step, 16);
  });

  test('zoomed far out the pitch doubles instead of drawing noise', () {
    final g = gridPoints(big, offset: Offset.zero, zoom: 0.2);
    expect(g.step, greaterThanOrEqualTo(14));
    expect(g.step, 25.6);
  });

  test('the point count stays bounded at every zoom on a large screen', () {
    var worst = 0;
    for (var z = 0.2; z <= 3.0; z += 0.01) {
      final g = gridPoints(big, offset: Offset(z * 137, z * 91), zoom: z);
      if (g.count > worst) worst = g.count;
    }
    // Worst case is just above the minimum step: (2560/14) x (1600/14) ~ 20 900.
    expect(worst, lessThan(21500));
  });

  test('a pan only shifts the lattice: the count stays about the same', () {
    final a = gridPoints(big, offset: const Offset(0, 0), zoom: 1).count;
    final b = gridPoints(big, offset: const Offset(17, 23), zoom: 1).count;
    expect((a - b).abs(), lessThan(200));
  });
}
