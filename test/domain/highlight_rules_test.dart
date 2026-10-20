import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/marks/highlight_rules.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:flutter_test/flutter_test.dart';

Highlight hl(String id, int a, int b, int color) => Highlight(
  id: id,
  docId: 'd',
  pageId: 'p',
  color: color,
  startChar: a,
  endChar: b,
  quote: 'q',
  rects: const [Box(0, 0, 10, 10)],
);

MarkSelection sel(int a, int b) => MarkSelection(
  start: a,
  end: b,
  rects: const [Box(0, 0, 10, 10)],
  quote: 'x',
);

void main() {
  const red = 1, blue = 2;

  test('nothing there: add', () {
    expect(planHighlight(const [], sel(0, 5), red), isA<HighlightAdd>());
  });

  test('equal range, same colour: duplicate', () {
    final p = planHighlight([hl('a', 0, 5, red)], sel(0, 5), red);
    expect((p as HighlightDuplicate).existing.id, 'a');
  });

  test('inside a same-colour highlight: duplicate', () {
    final p = planHighlight([hl('a', 0, 20, red)], sel(5, 8), red);
    expect(p, isA<HighlightDuplicate>());
  });

  test('a bigger selection around a smaller one merges', () {
    final p = planHighlight([hl('a', 5, 8, red)], sel(0, 20), red);
    final m = p as HighlightMerge;
    expect((m.start, m.end), (0, 20));
    expect(m.absorbed.map((h) => h.id), ['a']);
  });

  test('partial overlap merges to the union', () {
    final p = planHighlight([hl('a', 0, 10, red)], sel(5, 15), red);
    final m = p as HighlightMerge;
    expect((m.start, m.end), (0, 15));
  });

  test('bridging two highlights merges all three', () {
    final p = planHighlight(
      [hl('a', 0, 5, red), hl('b', 10, 15, red), hl('c', 30, 40, red)],
      sel(3, 12),
      red,
    );
    final m = p as HighlightMerge;
    expect(m.absorbed.map((h) => h.id).toSet(), {'a', 'b'});
    expect((m.start, m.end), (0, 15));
  });

  test('adjacent (touching) highlights are not an overlap', () {
    expect(
      planHighlight([hl('a', 0, 5, red)], sel(5, 9), red),
      isA<HighlightAdd>(),
    );
  });

  test('same words, other colour: recolour; partial overlap: add', () {
    expect(
      planHighlight([hl('a', 0, 5, red)], sel(0, 5), blue),
      isA<HighlightRecolor>(),
    );
    expect(
      planHighlight([hl('a', 0, 5, red)], sel(3, 9), blue),
      isA<HighlightAdd>(),
    );
  });

  test('a duplicate wins over a recolour of something else', () {
    final p = planHighlight(
      [hl('a', 0, 5, blue), hl('b', 0, 9, red)],
      sel(0, 5),
      red,
    );
    expect((p as HighlightDuplicate).existing.id, 'b');
  });

  test('regions are only duplicates of the same rectangle and colour', () {
    const region = MarkSelection(
      start: -1,
      end: -1,
      rects: [Box(0, 0, 10, 10)],
      quote: '',
      isRegion: true,
    );
    expect(
      planHighlight([hl('r', -1, -1, red)], region, red),
      isA<HighlightDuplicate>(),
    );
    expect(
      planHighlight([hl('r', -1, -1, blue)], region, red),
      isA<HighlightAdd>(),
    );
    expect(
      planHighlight([hl('t', 0, 5, red)], region, red),
      isA<HighlightAdd>(),
    );
  });
}
