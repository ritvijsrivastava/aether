import 'dart:math' as math;
import 'dart:ui';

import 'package:aether/features/canvas/pdf/tile_math.dart';
import 'package:flutter_test/flutter_test.dart';

const letter = Size(612, 792);

void main() {
  group('level of detail', () {
    test('scales are powers of sqrt(2)', () {
      expect(TileMath.scaleOf(0), 1);
      expect(TileMath.scaleOf(2), closeTo(2, 1e-12));
      expect(TileMath.scaleOf(-2), closeTo(0.5, 1e-12));
      expect(TileMath.scaleOf(6), closeTo(8, 1e-9));
    });

    test('rounds up so rendering is never softer than the screen needs', () {
      for (final s in [0.3, 0.5, 0.77, 1.0, 1.3, 2.0, 2.9, 5.5, 7.9]) {
        final lod = TileMath.lodFor(s, letter);
        expect(
          TileMath.scaleOf(lod),
          greaterThanOrEqualTo(s - 1e-9),
          reason: 'screen scale $s',
        );
        expect(
          TileMath.scaleOf(lod - 1),
          lessThan(s + 1e-9),
          reason: 'and no finer than needed',
        );
      }
    });

    test('an exact step does not jump to the next level', () {
      expect(TileMath.lodFor(TileMath.scaleOf(3), letter), 3);
      expect(TileMath.lodFor(1.0, letter), 0);
    });

    test('a pinch across a 41% range keeps one level', () {
      // Scales strictly between sqrt2^k-1 and sqrt2^k share level k.
      expect(TileMath.lodFor(1.05, letter), TileMath.lodFor(1.40, letter));
    });

    test('clamps to the supported range', () {
      expect(TileMath.lodFor(1000, letter), TileMath.maxLod);
      expect(TileMath.lodFor(1e-9, letter), TileMath.minLod);
      expect(TileMath.lodFor(-1, letter), TileMath.minLod);
    });

    test('300% zoom on a 2.625x display is within range', () {
      expect(TileMath.lodFor(3 * 2.625, letter), TileMath.maxLod);
    });

    test(
      'an oversized page backs off instead of asking for a gigapixel bitmap',
      () {
        const poster = Size(5000, 7000);
        final lod = TileMath.lodFor(8, poster);
        expect(
          poster.height * TileMath.scaleOf(lod),
          lessThanOrEqualTo(TileMath.maxPagePixels),
        );
        expect(lod, lessThan(TileMath.maxLod));
      },
    );

    test('baseLod fits the whole page in one tile', () {
      for (final p in [
        letter,
        const Size(792, 612),
        const Size(595, 842),
        const Size(100, 100),
        const Size(3000, 4000),
      ]) {
        final g = TileGeometry(p, TileMath.baseLod(p));
        expect((g.cols, g.rows), (1, 1), reason: '$p');
      }
    });

    test('baseLod is the finest such level', () {
      final lod = TileMath.baseLod(letter);
      final next = TileGeometry(letter, lod + 1);
      expect(next.cols * next.rows, greaterThan(1));
    });
  });

  group('geometry', () {
    test('tile grid covers the page exactly', () {
      final g = TileGeometry(letter, 4); // 4 px per point
      expect(g.fullWidth, 2448);
      expect(g.fullHeight, 3168);
      expect((g.cols, g.rows), (5, 7));
      var area = 0.0;
      for (var ty = 0; ty < g.rows; ty++) {
        for (var tx = 0; tx < g.cols; tx++) {
          final r = g.pixelRect(tx, ty);
          area += r.width * r.height;
        }
      }
      expect(area, g.fullWidth * g.fullHeight);
    });

    test('edge tiles are smaller than the tile size', () {
      final g = TileGeometry(letter, 4);
      expect(g.pixelRect(0, 0).size, const Size(512, 512));
      expect(
        g.pixelRect(4, 6).size,
        const Size(2448 - 4 * 512, 3168 - 6 * 512),
      );
    });

    test('page rects tile the page with no gaps or overlaps', () {
      final g = TileGeometry(letter, 3);
      final first = g.pageRect(0, 0);
      expect(first.topLeft, Offset.zero);
      final last = g.pageRect(g.cols - 1, g.rows - 1);
      expect(last.right, closeTo(letter.width, 1e-9));
      expect(last.bottom, closeTo(letter.height, 1e-9));
      for (var tx = 0; tx < g.cols - 1; tx++) {
        expect(
          g.pageRect(tx, 0).right,
          closeTo(g.pageRect(tx + 1, 0).left, 1e-9),
        );
      }
    });

    test('fractional page sizes still align on whole pixels', () {
      final g = TileGeometry(const Size(595.276, 841.89), 1);
      expect(g.fullWidth, g.fullWidth.roundToDouble());
      expect(g.pageRect(g.cols - 1, g.rows - 1).right, closeTo(595.276, 1e-6));
    });

    test('tilesIn returns only tiles that overlap the area', () {
      final g = TileGeometry(
        letter,
        4,
      ); // 128 pt per tile column, 128 pt per row
      final tiles = g.tilesIn(const Rect.fromLTWH(130, 130, 10, 10)).toList();
      expect(tiles, [(1, 1)]);
      final span = g.tilesIn(const Rect.fromLTWH(100, 100, 100, 100)).toList();
      expect(span.toSet(), {(0, 0), (1, 0), (0, 1), (1, 1)});
    });

    test('tilesIn clips to the page and ignores empty or outside areas', () {
      final g = TileGeometry(letter, 2);
      expect(g.tilesIn(const Rect.fromLTWH(-500, -500, 100, 100)), isEmpty);
      expect(g.tilesIn(const Rect.fromLTWH(10, 10, 0, 50)), isEmpty);
      final all = g
          .tilesIn(const Rect.fromLTWH(-100, -100, 5000, 5000))
          .toList();
      expect(all.length, g.cols * g.rows);
    });

    test(
      'an area ending exactly on a tile edge does not pull in the next tile',
      () {
        final g = TileGeometry(letter, 4);
        final tiles = g
            .tilesIn(const Rect.fromLTWH(0, 0, 128, 128))
            .toList(); // exactly tile (0,0)
        expect(tiles, [(0, 0)]);
      },
    );

    test('keys compare by value', () {
      expect(const TileKey(1, 2, 3, 4), const TileKey(1, 2, 3, 4));
      expect(
        const TileKey(1, 2, 3, 4).hashCode,
        const TileKey(1, 2, 3, 4).hashCode,
      );
      expect(const TileKey(1, 2, 3, 4) == const TileKey(1, 2, 3, 5), isFalse);
    });
  });

  test('visible tile count at full screen stays small on a big display', () {
    // 2560x1600 px viewport at 1:1: about 6x4 tiles, a few MB.
    final g = TileGeometry(letter, TileMath.lodFor(1.0, letter));
    final n = g.tilesIn(const Rect.fromLTWH(0, 0, 2560, 1600)).length;
    expect(n, lessThanOrEqualTo(math.max(4, 6 * 4)));
  });
}
