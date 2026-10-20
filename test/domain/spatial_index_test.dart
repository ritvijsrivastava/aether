import 'dart:math';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/marks/highlight_index.dart';
import 'package:aether/domain/marks/spatial_grid.dart';
import 'package:aether/domain/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

Highlight hl(String id, String page, List<Box> rects) => Highlight(
  id: id,
  docId: 'd',
  pageId: page,
  color: Swatch.claim,
  startChar: 0,
  endChar: 5,
  quote: 'q',
  rects: rects,
);

void main() {
  group('SpatialGrid', () {
    test('finds what overlaps an area and nothing else', () {
      final g = SpatialGrid()
        ..put('a', const Box(10, 10, 50, 30))
        ..put('b', const Box(300, 300, 340, 320))
        ..put('c', const Box(120, 10, 200, 30)); // spans two cells
      expect(g.query(const Box(0, 0, 60, 60)), {'a'});
      expect(g.query(const Box(110, 0, 130, 20)), {'c'});
      expect(g.query(const Box(190, 0, 310, 310)), {'c', 'b'});
      expect(g.query(const Box(500, 500, 600, 600)), isEmpty);
    });

    test('touching counts, near misses do not', () {
      final g = SpatialGrid()..put('a', const Box(10, 10, 20, 20));
      expect(g.query(const Box(20, 20, 30, 30)), {'a'});
      expect(g.query(const Box(20.5, 20.5, 30, 30)), isEmpty);
    });

    test('a big mark is found from any cell it covers, once', () {
      final g = SpatialGrid()..put('big', const Box(0, 0, 1000, 1000));
      expect(g.query(const Box(900, 900, 910, 910)), {'big'});
      expect(g.query(const Box(0, 0, 1000, 1000)), {'big'});
    });

    test('put replaces, remove forgets, clear empties', () {
      final g = SpatialGrid()..put('a', const Box(0, 0, 10, 10));
      g.put('a', const Box(500, 500, 510, 510));
      expect(g.query(const Box(0, 0, 20, 20)), isEmpty);
      expect(g.query(const Box(490, 490, 520, 520)), {'a'});
      expect(g.length, 1);
      g.remove('a');
      g.remove('a'); // twice is fine
      expect(g.length, 0);
      g.put('b', const Box(0, 0, 1, 1));
      g.clear();
      expect(g.query(const Box(-5, -5, 5, 5)), isEmpty);
    });

    test('works across negative coordinates', () {
      final g = SpatialGrid()..put('n', const Box(-300, -300, -250, -280));
      expect(g.query(const Box(-290, -290, -260, -285)), {'n'});
      expect(g.query(const Box(0, 0, 10, 10)), isEmpty);
    });

    test('agrees with a brute-force scan on random marks', () {
      final rnd = Random(7);
      final g = SpatialGrid();
      final boxes = <String, Box>{};
      for (var i = 0; i < 2000; i++) {
        final x = rnd.nextDouble() * 600, y = rnd.nextDouble() * 800;
        final b = Box(
          x,
          y,
          x + rnd.nextDouble() * 80,
          y + rnd.nextDouble() * 20,
        );
        boxes['m$i'] = b;
        g.put('m$i', b);
      }
      for (var q = 0; q < 300; q++) {
        final x = rnd.nextDouble() * 600, y = rnd.nextDouble() * 800;
        final area = Box(
          x,
          y,
          x + rnd.nextDouble() * 60,
          y + rnd.nextDouble() * 60,
        );
        final expected = {
          for (final e in boxes.entries)
            if (e.value.x0 <= area.x1 &&
                e.value.x1 >= area.x0 &&
                e.value.y0 <= area.y1 &&
                e.value.y1 >= area.y0)
              e.key,
        };
        expect(g.query(area), expected);
      }
    });

    test('a point query in a crowded page is fast', () {
      final g = SpatialGrid();
      final rnd = Random(3);
      for (var i = 0; i < 20000; i++) {
        final x = rnd.nextDouble() * 600, y = rnd.nextDouble() * 800;
        g.put('m$i', Box(x, y, x + 30, y + 10));
      }
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        g.query(Box(i % 600.0, i % 800.0, i % 600.0 + 4, i % 800.0 + 4));
      }
      // 1,000 queries over 20,000 marks: far under a millisecond each.
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('HighlightIndex', () {
    // A line of text 8 pt tall: thinner than the 16 px minimum at zoom 1.
    const thin = Box(100, 200, 300, 208);

    test('hits inside a rect', () {
      final i = HighlightIndex()..put(hl('a', 'p', [thin]));
      expect(i.hitTest('p', 150, 204, 1)?.id, 'a');
    });

    test('a thin line is 16 screen px tall to hit', () {
      final i = HighlightIndex()..put(hl('a', 'p', [thin]));
      // At zoom 1: 4 pt above the 8 pt rect's top is 4 px: inside the 16 px.
      expect(i.hitTest('p', 150, 196.5, 1)?.id, 'a');
      expect(i.hitTest('p', 150, 211.5, 1)?.id, 'a');
      // The 10 px tolerance still applies sideways and beyond.
      expect(i.hitTest('p', 150, 190, 1)?.id, 'a', reason: '10 px above');
      expect(i.hitTest('p', 150, 180, 1), isNull);
      expect(i.hitTest('p', 305, 204, 1)?.id, 'a');
      expect(i.hitTest('p', 315, 204, 1), isNull);
    });

    test('the reach is the same in screen pixels at any zoom', () {
      final i = HighlightIndex()..put(hl('a', 'p', [thin]));
      // Zoomed out to 25%: 10 px is 40 pt.
      expect(i.hitTest('p', 150, 204 - 44, 0.25)?.id, 'a');
      expect(i.hitTest('p', 150, 204 - 70, 0.25), isNull);
      // Zoomed in to 400%: 10 px is 2.5 pt.
      expect(i.hitTest('p', 150, 200 - 2, 4)?.id, 'a');
      expect(i.hitTest('p', 150, 200 - 6, 4), isNull);
    });

    test(
      'works on any line of a multi-line highlight, not the gap beside it',
      () {
        final i = HighlightIndex()
          ..put(
            hl('m', 'p', const [
              Box(100, 100, 300, 110),
              Box(100, 300, 150, 310),
            ]),
          );
        expect(i.hitTest('p', 120, 105, 1)?.id, 'm');
        expect(i.hitTest('p', 120, 305, 1)?.id, 'm');
        expect(
          i.hitTest('p', 120, 200, 1),
          isNull,
          reason: 'between the lines',
        );
      },
    );

    test('the smaller highlight wins: a word beats its sentence', () {
      final i = HighlightIndex()
        ..put(hl('sentence', 'p', const [Box(100, 100, 400, 110)]))
        ..put(hl('word', 'p', const [Box(200, 100, 240, 110)]));
      expect(i.hitTest('p', 220, 105, 1)?.id, 'word');
      expect(i.hitTest('p', 350, 105, 1)?.id, 'sentence');
    });

    test('of two equal highlights the newer wins', () {
      final i = HighlightIndex()
        ..put(hl('old', 'p', const [Box(100, 100, 200, 110)]))
        ..put(hl('new', 'p', const [Box(100, 100, 200, 110)]));
      expect(i.hitTest('p', 150, 105, 1)?.id, 'new');
    });

    test('pages are separate; remove and clear forget', () {
      final i = HighlightIndex()
        ..put(hl('a', 'p1', const [Box(0, 0, 100, 10)]))
        ..put(hl('b', 'p2', const [Box(0, 0, 100, 10)]));
      expect(i.hitTest('p1', 50, 5, 1)?.id, 'a');
      expect(i.hitTest('p2', 50, 5, 1)?.id, 'b');
      expect(i.hitTest('p3', 50, 5, 1), isNull);
      i.remove('a');
      expect(i.hitTest('p1', 50, 5, 1), isNull);
      i.clear();
      expect(i.hitTest('p2', 50, 5, 1), isNull);
    });

    test('touching is exact: no tolerance, no minimum height', () {
      final i = HighlightIndex()..put(hl('a', 'p', [thin]));
      expect(i.touching('p', 150, 204, 1).single.id, 'a');
      expect(i.touching('p', 150, 215, 5), isEmpty, reason: '7 pt below, r 5');
      expect(i.touching('p', 150, 213, 5).single.id, 'a', reason: '5 pt below');
      expect(i.touching('p', 150, 204, 1).length, 1);
      expect(i.touching('other', 150, 204, 5), isEmpty);
    });

    test('touching finds every line of a multi-line highlight, and many highlights', () {
      final i = HighlightIndex()
        ..put(
          hl('m', 'p', const [
            Box(100, 100, 300, 110),
            Box(100, 300, 150, 310),
          ]),
        )
        ..put(hl('n', 'p', const [Box(120, 305, 140, 312)]));
      expect({for (final h in i.touching('p', 130, 306, 4)) h.id}, {'m', 'n'});
      expect(i.touching('p', 130, 200, 4), isEmpty);
    });

    test('nearest finds the closest highlight within reach, or none', () {
      final i = HighlightIndex()
        ..put(hl('near', 'p', const [Box(100, 100, 200, 110)]))
        ..put(hl('far', 'p', const [Box(100, 300, 200, 310)]));
      expect(i.nearest('p', 150, 125, 30)?.id, 'near');
      expect(i.nearest('p', 150, 125, 10), isNull, reason: '15 away, reach 10');
      expect(i.nearest('p', 150, 290, 30)?.id, 'far');
      expect(
        i.nearest('p', 150, 200, 100)?.id,
        'near',
        reason: 'closer of the two',
      );
      expect(i.nearest('other', 150, 105, 30), isNull);
    });

    test('putting a highlight again replaces it', () {
      final i = HighlightIndex()
        ..put(hl('a', 'p', const [Box(0, 0, 100, 10)]))
        ..put(hl('a', 'p', const [Box(500, 500, 600, 510)]));
      expect(i.hitTest('p', 50, 5, 1), isNull);
      expect(i.hitTest('p', 550, 505, 1)?.id, 'a');
    });
  });
}
