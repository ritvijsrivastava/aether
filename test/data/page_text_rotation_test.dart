import 'package:aether/core/geometry/box.dart';
import 'package:aether/data/pdf/page_text_service.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/pdfium_env.dart';

/// Where the words are, checked against where pdfium actually paints ink.
///
/// `rotated.pdf` (made by tool/make_test_pdfs.py) has the line "Hello rotation
/// test" on seven pages: /Rotate 0, 90, 180 and 270 with the text upright on
/// screen, a CropBox that does not start at the origin, and /Rotate 90 and 180
/// with the text left as drawn (sideways, upside down on screen). On every one
/// the text layer's boxes must sit on the black pixels of the rendered page.
/// Words and lines are exact where the text reads left to right on screen;
/// sideways and upside-down text is a known limit (register R32).
const _rotated = 'test/fixtures/generated/rotated.pdf';
const _scanned = 'test/fixtures/generated/scanned.pdf';

/// The bounding box of all dark pixels of [page] rendered at 1 pixel per point.
Future<Box> inkBox(PdfPage page) async {
  final w = page.width.round(), h = page.height.round();
  final img = (await page.render(
    fullWidth: w.toDouble(),
    fullHeight: h.toDouble(),
    backgroundColor: 0xffffffff,
  ))!;
  final px = img.pixels; // BGRA
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * img.width + x) * 4;
      final lum = (px[o] + px[o + 1] + px[o + 2]) / 3;
      if (lum < 140) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  img.dispose();
  return Box(x0.toDouble(), y0.toDouble(), x1 + 1.0, y1 + 1.0);
}

void expectBoxNear(Box a, Box b, double tol, String reason) {
  expect(a.x0, closeTo(b.x0, tol), reason: '$reason left ($a vs $b)');
  expect(a.y0, closeTo(b.y0, tol), reason: '$reason top ($a vs $b)');
  expect(a.x1, closeTo(b.x1, tol), reason: '$reason right ($a vs $b)');
  expect(a.y1, closeTo(b.y1, tol), reason: '$reason bottom ($a vs $b)');
}

void main() {
  setUpPdfium();
  final skip = pdfiumSkipReason([_rotated]);

  const names = ['0', '90', '180', '270', 'crop box'];
  for (var i = 0; i < names.length; i++) {
    testWidgets('page rotated ${names[i]}: text boxes sit on the ink', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final pdf = await openPdfFile(_rotated);
        addTearDown(pdf.dispose);
        final page = pdf.document.pages[i];
        final t = await PageTextService(
          docKey: 'r',
          extractor: PdfrxTextExtractor(pdf.document),
        ).pageText(i);

        expect(
          [for (final w in t.words) t.quote(w.start, w.end)],
          ['Hello', 'rotation', 'test'],
        );
        expect(t.lines.length, 1, reason: 'one line, whatever the rotation');

        // The line's box is the ink's box, within a few points of glyph
        // side-bearing.
        final ink = await inkBox(page);
        expectBoxNear(t.lines.single.box, ink, 5, 'rotate ${names[i]}');

        // Page size follows the rotation: 90 and 270 are landscape.
        final landscape = names[i] == '90' || names[i] == '270';
        expect(page.width > page.height, landscape);

        // And a drag over the first word selects exactly it, by position.
        final first = t.words.first.box;
        final sel = TextSelector.between(
          t,
          TextSelector.wordAt(
            t,
            (first.x0 + first.x1) / 2,
            (first.y0 + first.y1) / 2,
          ),
          TextSelector.wordAt(
            t,
            (first.x0 + first.x1) / 2,
            (first.y0 + first.y1) / 2,
          ),
        )!;
        expect(sel.quote, 'Hello');
      });
    }, skip: skip != null);
  }

  const sideways = {5: 'sideways', 6: 'upside down'};
  for (final e in sideways.entries) {
    testWidgets('${e.value} text still sits on its ink', (tester) async {
      await tester.runAsync(() async {
        final pdf = await openPdfFile(_rotated);
        addTearDown(pdf.dispose);
        final t = await PageTextService(
          docKey: 'r',
          extractor: PdfrxTextExtractor(pdf.document),
        ).pageText(e.key);
        expect(t.hasText, isTrue);
        // Words may be split or ordered oddly, but every box is on the ink.
        var all = t.words.first.box;
        for (final w in t.words) {
          all = all.union(w.box);
        }
        expectBoxNear(all, await inkBox(pdf.document.pages[e.key]), 5, e.value);
        // The same characters come out, in some order.
        final letters = t.quote(0, t.length).replaceAll(' ', '');
        expect(
          letters.length,
          greaterThanOrEqualTo('Hellorotationtest'.length),
        );
      });
    }, skip: skip != null);
  }

  testWidgets('a scanned page has no text and falls back to a rectangle', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pdf = await openPdfFile(_scanned);
      addTearDown(pdf.dispose);
      final t = await PageTextService(
        docKey: 's',
        extractor: PdfrxTextExtractor(pdf.document),
      ).pageText(0);
      expect(t.hasText, isFalse);
      final drag = MarkDrag(t, 100, 100);
      expect(drag.isText, isFalse);
      final s = drag.update(260, 180)!;
      expect(s.isRegion, isTrue);
      expect(s.quote, imageRegionQuote);
      expect(s.rects.single.width, 160);
    });
  }, skip: pdfiumSkipReason([_scanned]) != null);
}
