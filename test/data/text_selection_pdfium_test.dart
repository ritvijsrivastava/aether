import 'package:aether/data/pdf/page_text_service.dart';
import 'package:aether/domain/text/page_text.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pdfium_env.dart';

/// Drag-select acceptance on the fixture PDFs (SPEC §18, M3): the text a user
/// drags over is the text the highlight quotes.
const _prose = 'test/fixtures/mapreduce/mapreduce.pdf';
const _math = 'test/fixtures/navier-stokes.pdf';

int wordIndex(PageText t, String text, {int nth = 0}) {
  var seen = 0;
  for (var i = 0; i < t.words.length; i++) {
    if (t.quote(t.words[i].start, t.words[i].end) == text && seen++ == nth) {
      return i;
    }
  }
  throw StateError('no word "$text" #$nth on the page');
}

({double x, double y}) centre(PageText t, int word) {
  final b = t.words[word].box;
  return (x: (b.x0 + b.x1) / 2, y: (b.y0 + b.y1) / 2);
}

/// Pointer-down on [from] and release on [to], like a finger or pen.
MarkSelection? drag(PageText t, int from, int to) {
  final a = centre(t, from), b = centre(t, to);
  final d = MarkDrag(t, a.x, a.y);
  expect(d.isText, isTrue);
  return d.update(b.x, b.y);
}

void main() {
  setUpPdfium();
  final skip = pdfiumSkipReason([_prose, _math]);

  Future<PageTextService> open(String path, String key) async {
    final pdf = await openPdfFile(path);
    addTearDown(pdf.dispose);
    return PageTextService(
      docKey: key,
      extractor: PdfrxTextExtractor(pdf.document),
    );
  }

  group('drag-select on real PDFs', () {
    testWidgets('across three lines of the abstract', (tester) async {
      await tester.runAsync(() async {
        final t = await (await open(_prose, 'm')).pageText(0);
        final s = drag(t, wordIndex(t, 'programming'), wordIndex(t, 'sets.'))!;
        expect(
          s.quote,
          'programming model and an associated implementation for processing '
          'and generating large data sets.',
        );
        expect(s.rects.length, 3);
        // Rows are even, and each stays inside the text block's margins.
        expect(s.rects.map((r) => r.height.round()).toSet().length, 1);
        for (final r in s.rects) {
          expect(r.x0, greaterThan(60));
          expect(r.x1, lessThan(560));
        }
      });
    }, skip: skip != null);

    testWidgets('backwards, and across a paragraph on page 2', (tester) async {
      await tester.runAsync(() async {
        final t = await (await open(_prose, 'm')).pageText(1);
        final from = wordIndex(t, 'The'), to = wordIndex(t, 'pairs.');
        const expected =
            'The computation takes a set of input key/value pairs, and '
            'produces a set of output key/value pairs.';
        expect(drag(t, from, to)!.quote, expected);
        expect(drag(t, to, from)!.quote, expected);
      });
    }, skip: skip != null);

    testWidgets('a tap selects one word; a double tap, its sentence', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final t = await (await open(_prose, 'm')).pageText(1);
        final w = wordIndex(t, 'computation');
        final c = centre(t, w);
        expect(MarkDrag(t, c.x, c.y).selection!.quote, 'computation');
        expect(
          TextSelector.sentenceAt(t, w)!.quote,
          'The computation takes a set of input key/value pairs, and produces '
          'a set of output key/value pairs.',
          reason: 'the heading "2 Programming Model" above is not included',
        );
        final user = wordIndex(t, 'user', nth: 0);
        expect(
          TextSelector.sentenceAt(t, user)!.quote,
          startsWith('The user of the MapReduce library'),
        );
      });
    }, skip: skip != null);

    testWidgets('a line of the math paper, and across a displayed equation', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final t = await (await open(_math, 'n')).pageText(7);
        final from = wordIndex(t, 'The'), to = wordIndex(t, 'give');
        expect(
          drag(t, from, to)!.quote,
          'The leading radial pressure balance and the normalization at radial '
          'infinity give',
        );
        // Through the equation: it must include the text on both sides, not
        // crash, and not make absurd rects.
        final across = drag(
          t,
          wordIndex(t, 'give'),
          wordIndex(t, 'construction'),
        )!;
        expect(across.quote, startsWith('give'));
        expect(across.quote, contains('dx'));
        expect(across.quote, endsWith('construction'));
        for (final r in across.rects) {
          expect(r.height, lessThan(60));
        }
      });
    }, skip: skip != null);

    testWidgets('selecting every line of every page gives sane rects', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final (path, key) in [(_prose, 'm'), (_math, 'n')]) {
          final pdf = await openPdfFile(path);
          addTearDown(pdf.dispose);
          final s = PageTextService(
            docKey: key,
            extractor: PdfrxTextExtractor(pdf.document),
            maxPagesInMemory: 2,
          );
          for (var p = 0; p < pdf.pageSizes.length; p++) {
            final t = await s.pageText(p);
            final size = pdf.pageSizes[p];
            for (var l = 0; l < t.lines.length; l++) {
              final line = t.lines[l];
              final sel = TextSelector.between(
                t,
                line.firstWord,
                line.endWord - 1,
              );
              final where = '$key p${p + 1} line $l';
              expect(sel, isNotNull, reason: where);
              expect(sel!.rects.length, 1, reason: where);
              expect(sel.quote, isNotEmpty, reason: where);
              final r = sel.rects.single;
              expect(r.width, greaterThan(0), reason: where);
              expect(
                r.height,
                inInclusiveRange(TextSelector.minRowHeight, 80),
                reason: where,
              );
              expect(r.x0, greaterThan(-10), reason: where);
              expect(r.x1, lessThan(size.width + 10), reason: where);
            }
            // The whole page as one selection: one rect per line at most.
            if (t.hasText) {
              final all = TextSelector.between(t, 0, t.words.length - 1)!;
              expect(all.rects.length, lessThanOrEqualTo(t.lines.length));
            }
          }
        }
      });
    }, skip: skip != null);
  });
}
