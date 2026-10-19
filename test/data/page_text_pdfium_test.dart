import 'dart:io';

import 'package:aether/data/pdf/page_text_service.dart';
import 'package:aether/domain/text/page_text.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pdfium_env.dart';

/// Real pdfium text extraction against two third-party fixtures (git-ignored):
/// a two-column-era prose paper and a 166-page LaTeX paper full of math.
const _prose = 'test/fixtures/mapreduce/mapreduce.pdf';
const _math = 'test/fixtures/navier-stokes.pdf';

String lineText(PageText t, int line) {
  final l = t.lines[line];
  return t.quote(t.words[l.firstWord].start, t.words[l.endWord - 1].end);
}

/// Structural facts that must hold for any page, however ugly the layout.
void checkInvariants(PageText t, double w, double h, String where) {
  var prevEnd = 0;
  for (var i = 0; i < t.words.length; i++) {
    final word = t.words[i];
    expect(
      word.start,
      greaterThanOrEqualTo(prevEnd),
      reason: '$where w$i order',
    );
    expect(word.end, greaterThan(word.start), reason: '$where w$i empty');
    prevEnd = word.end;
    final b = word.box;
    expect(b.width, greaterThan(0), reason: '$where w$i zero width');
    expect(b.height, greaterThan(0), reason: '$where w$i zero height');
    expect(b.x0, greaterThan(-10), reason: '$where w$i off page');
    expect(b.y0, greaterThan(-10), reason: '$where w$i off page');
    expect(b.x1, lessThan(w + 10), reason: '$where w$i off page');
    expect(b.y1, lessThan(h + 10), reason: '$where w$i off page');
    expect(t.wordAtChar(word.start), i, reason: '$where w$i lookup');
    expect(t.wordAtChar(word.end - 1), i, reason: '$where w$i lookup');
    expect(word.line, inInclusiveRange(0, t.lines.length - 1));
  }
  var next = 0;
  for (var l = 0; l < t.lines.length; l++) {
    final line = t.lines[l];
    expect(line.firstWord, next, reason: '$where line $l not contiguous');
    expect(line.endWord, greaterThan(line.firstWord));
    for (var k = line.firstWord; k < line.endWord; k++) {
      expect(t.words[k].line, l);
    }
    next = line.endWord;
  }
  expect(next, t.words.length, reason: '$where lines cover all words');
}

void main() {
  setUpPdfium();
  final skip = pdfiumSkipReason([_prose, _math]);

  group('real pdfium text', () {
    late Directory cacheDir;
    setUp(() async => cacheDir = await Directory.systemTemp.createTemp('axt'));
    tearDown(() => cacheDir.delete(recursive: true));

    testWidgets('prose page: exact lines, no stray splits at punctuation', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final pdf = await openPdfFile(_prose);
        addTearDown(pdf.dispose);
        final s = PageTextService(
          docKey: 'm',
          extractor: PdfrxTextExtractor(pdf.document),
        );
        final p1 = await s.pageText(0);
        expect(p1.hasText, isTrue);
        expect(
          lineText(p1, 0),
          'MapReduce: Simplified Data Processing on Large Clusters',
        );
        expect(lineText(p1, 1), 'Jeffrey Dean and Sanjay Ghemawat');
        expect(lineText(p1, 2), 'jeff@google.com, sanjay@google.com');
        expect(lineText(p1, 3), 'Google, Inc.');

        final p2 = await s.pageText(1);
        expect(
          lineText(p2, 3),
          'The computation takes a set of input key/value pairs, and',
        );
        final p6 = await s.pageText(5);
        expect(
          lineText(p6, 7),
          'form MapReduce computations with M = 200, 000 and',
        );
        checkInvariants(p1, 612, 792, 'mapreduce p1');
      });
    }, skip: skip != null);

    testWidgets('a word hyphenated across lines reads as one word', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final pdf = await openPdfFile(_prose);
        addTearDown(pdf.dispose);
        final s = PageTextService(
          docKey: 'm',
          extractor: PdfrxTextExtractor(pdf.document),
        );
        final t = await s.pageText(0);
        // Lines 5 and 6: "...an associ" / "ated implementation for ...".
        final a = t.lines[5], b = t.lines[6];
        final q = t.quote(
          t.words[a.firstWord].start,
          t.words[b.endWord - 1].end,
        );
        expect(q, contains('associated implementation'));
      });
    }, skip: skip != null);

    testWidgets('math paper: prose is exact, math is sane', (tester) async {
      await tester.runAsync(() async {
        final pdf = await openPdfFile(_math);
        addTearDown(pdf.dispose);
        final s = PageTextService(
          docKey: 'n',
          extractor: PdfrxTextExtractor(pdf.document),
        );
        final p1 = await s.pageText(0);
        expect(lineText(p1, 0), 'FINITE TIME BLOWUP FOR NAVIER–STOKES');
        expect(
          lineText(p1, 2),
          'Abstract. For every positive viscosity, we construct a solution of '
          'the three-dimensional',
        );

        final p8 = await s.pageText(7);
        final all = [for (var i = 0; i < p8.lines.length; i++) lineText(p8, i)];
        expect(
          all,
          contains(
            'The leading radial pressure balance and the normalization at '
            'radial infinity give',
          ),
        );
        expect(
          all.any((l) => l.contains('Π(X, η)') && l.contains('∫')),
          isTrue,
          reason: 'the displayed equation is kept as one line',
        );
      });
    }, skip: skip != null);

    testWidgets('every page of both papers is structurally sound, and fast', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final (path, key) in [(_prose, 'm'), (_math, 'n')]) {
          final pdf = await openPdfFile(path);
          addTearDown(pdf.dispose);
          final s = PageTextService(
            docKey: key,
            extractor: PdfrxTextExtractor(pdf.document),
            maxPagesInMemory: 4,
          );
          final sw = Stopwatch()..start();
          var withText = 0;
          for (var i = 0; i < pdf.pageSizes.length; i++) {
            final t = await s.pageText(i);
            final size = pdf.pageSizes[i];
            checkInvariants(t, size.width, size.height, '$key p${i + 1}');
            if (t.hasText) withText++;
          }
          final perPage = sw.elapsedMilliseconds / pdf.pageSizes.length;
          // ignore: avoid_print
          print(
            '$path: ${pdf.pageSizes.length} pages, '
            '${perPage.toStringAsFixed(1)} ms/page, $withText with text',
          );
          expect(withText, greaterThan(pdf.pageSizes.length * 0.9));
          expect(perPage, lessThan(100), reason: 'budget is 100 ms per page');
        }
      });
    }, skip: skip != null);

    testWidgets('the disk cache returns identical text and skips pdfium', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final pdf = await openPdfFile(_math);
        addTearDown(pdf.dispose);
        final cache = PageTextCache(cacheDir);
        final first = PageTextService(
          docKey: 'n',
          extractor: PdfrxTextExtractor(pdf.document),
          cache: cache,
        );
        final a = await first.pageText(7);
        final second = PageTextService(
          docKey: 'n',
          extractor: PdfrxTextExtractor(pdf.document),
          cache: cache,
        );
        final b = await second.pageText(7);
        expect(second.diskHits, 1);
        expect(second.extractions, 0);
        expect(b.length, a.length);
        expect(b.words.length, a.words.length);
        expect(b.lines.length, a.lines.length);
        for (var i = 0; i < a.lines.length; i++) {
          expect(lineText(b, i), lineText(a, i));
        }
      });
    }, skip: skip != null);
  });
}
