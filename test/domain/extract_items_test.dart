import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/export/extract_items.dart';
import 'package:aether/domain/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

Highlight hl(
  String id,
  String page,
  int start, {
  Meaning m = Meaning.claim,
  String quote = 'q',
  Box rect = const Box(0, 0, 10, 10),
}) => Highlight(
  id: id,
  docId: 'd',
  pageId: page,
  meaning: m,
  startChar: start,
  endChar: start < 0 ? -1 : start + 5,
  quote: quote,
  rects: [rect],
);

void main() {
  const pages = {'p0': 0, 'p1': 1, 'p2': 2};

  test('orders by page, then by position in the text', () {
    final items = buildExtract([
      hl('c', 'p1', 5),
      hl('a', 'p0', 90),
      hl('b', 'p0', 10),
      hl('d', 'p2', 0),
    ], pages);
    expect([for (final i in items) i.highlight.id], ['b', 'a', 'c', 'd']);
    expect([for (final i in items) i.pageNumber], [1, 1, 2, 3]);
  });

  test('free rectangles come after the text on their page, top to bottom', () {
    final items = buildExtract([
      hl('r2', 'p0', -1, rect: const Box(0, 300, 50, 350)),
      hl('t', 'p0', 400),
      hl('r1', 'p0', -1, rect: const Box(0, 100, 50, 150)),
      hl('next', 'p1', 0),
    ], pages);
    expect([for (final i in items) i.highlight.id], ['t', 'r1', 'r2', 'next']);
    expect(items[1].isRegion, isTrue);
    expect(items[0].isRegion, isFalse);
  });

  test('a filter keeps one meaning', () {
    final all = [
      hl('a', 'p0', 1, m: Meaning.claim),
      hl('b', 'p0', 2, m: Meaning.method),
      hl('c', 'p0', 3, m: Meaning.method),
    ];
    expect(buildExtract(all, pages, only: Meaning.method).length, 2);
    expect(buildExtract(all, pages, only: Meaning.question), isEmpty);
    expect(buildExtract(all, pages).length, 3);
  });

  test('a highlight whose page is gone sorts last', () {
    final items = buildExtract([
      hl('lost', 'gone', 0),
      hl('a', 'p2', 0),
    ], pages);
    expect(items.last.highlight.id, 'lost');
    expect(items.last.pageIndex, -1);
  });

  test('equal positions keep a stable order', () {
    final a = buildExtract([hl('y', 'p0', 5), hl('x', 'p0', 5)], pages);
    final b = buildExtract([hl('x', 'p0', 5), hl('y', 'p0', 5)], pages);
    expect([for (final i in a) i.highlight.id], ['x', 'y']);
    expect([for (final i in b) i.highlight.id], ['x', 'y']);
  });

  test('empty in, empty out', () {
    expect(buildExtract(const [], pages), isEmpty);
  });
}
