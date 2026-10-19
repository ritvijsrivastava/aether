import 'dart:typed_data';

import 'package:aether/domain/text/page_text.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Glyphs 6 pt wide and 10 pt tall, lines 14 pt apart from y = 100, with real
/// space boxes and a generated newline between lines.
PageText layout(List<String> lines, {double x0 = 72, List<double>? ys}) {
  final codes = <int>[];
  final boxes = <double>[];
  for (var l = 0; l < lines.length; l++) {
    final y = ys?[l] ?? 100.0 + l * 14;
    var x = x0;
    for (final r in lines[l].runes) {
      codes.add(r);
      boxes.addAll([x, y, x + 6, y + 10]);
      x += 6;
    }
    if (l < lines.length - 1) {
      codes.add(0x0A);
      boxes.addAll([0, 0, 0, 0]);
    }
  }
  return PageText.build(Int32List.fromList(codes), Float32List.fromList(boxes));
}

void main() {
  group('wordAt', () {
    final t = layout(['the quick brown', 'fox jumps over']);

    test('hits the word under the point', () {
      // "quick" spans x 96..126 on line 0 (y 100..110).
      expect(
        t.quote(t.words[t.words[1].start == 4 ? 1 : 1].start, t.words[1].end),
        'quick',
      );
      expect(TextSelector.wordAt(t, 100, 105), 1);
      expect(TextSelector.wordAt(t, 72, 100), 0);
    });

    test('accepts a point within the tolerance, not beyond it', () {
      expect(
        TextSelector.wordAt(t, 100, 94, tolerance: 8),
        1,
        reason: '6 pt above the line is still near enough',
      );
      expect(TextSelector.wordAt(t, 100, 200, tolerance: 8), -1);
      expect(TextSelector.wordAt(t, 20, 105, tolerance: 8), -1);
    });

    test('between two words picks the nearer one', () {
      // The gap between "the" (ends 90) and "quick" (starts 96) is 90..96.
      expect(TextSelector.wordAt(t, 91, 105), 0);
      expect(TextSelector.wordAt(t, 95, 105), 1);
    });

    test('an empty page yields -1', () {
      expect(TextSelector.wordAt(PageText.empty, 10, 10), -1);
      expect(TextSelector.wordNear(PageText.empty, 10, 10), -1);
    });
  });

  group('wordNear', () {
    test('in a margin, picks the line then the word along it', () {
      final t = layout(['the quick brown', 'fox jumps over']);
      expect(TextSelector.wordNear(t, 0, 105), 0, reason: 'left margin');
      expect(TextSelector.wordNear(t, 500, 105), 2, reason: 'right margin');
      expect(
        TextSelector.wordNear(t, 100, 300),
        4,
        reason: 'below the page text → last line, nearest word',
      );
    });

    test('between lines, goes to the nearer line', () {
      final t = layout(['aaa bbb', 'ccc ddd']);
      // Line 0: y 100..110, line 1: y 114..124. y = 111 is nearer line 0.
      expect(TextSelector.wordNear(t, 73, 111), 0);
      expect(TextSelector.wordNear(t, 73, 113), 2);
    });

    test('side-by-side columns: the nearer column wins', () {
      // Content order is the whole left column, then the whole right one.
      final left = layout(['alpha beta', 'one two']);
      final right = layout(['gamma delta', 'three four'], x0: 300);
      final t = PageText.build(
        Int32List.fromList([...left.codes, ...right.codes]),
        Float32List.fromList([...left.boxes, ...right.boxes]),
      );
      expect(t.lines.length, 4);
      String at(double x, double y) {
        final w = TextSelector.wordNear(t, x, y);
        return t.quote(t.words[w].start, t.words[w].end);
      }

      expect(at(310, 105), 'gamma');
      expect(at(80, 105), 'alpha');
      expect(at(310, 119), 'three');
      expect(
        at(270, 119),
        'three',
        reason: 'the gutter, nearer the right text',
      );
    });
  });

  group('between and rectsFor', () {
    final t = layout(['the quick brown', 'fox jumps over', 'the lazy dog']);

    test('one word: one rect equal to the word box', () {
      final s = TextSelector.between(t, 1, 1)!;
      expect(s.quote, 'quick');
      expect(s.rects.length, 1);
      expect(s.rects.single.x0, 96);
      expect(s.rects.single.x1, 126);
      expect(s.rects.single.y0, 100);
      expect(s.rects.single.y1, 110);
    });

    test('either order gives the same selection', () {
      final a = TextSelector.between(t, 1, 4)!;
      final b = TextSelector.between(t, 4, 1)!;
      expect(a.quote, b.quote);
      expect(a.start, b.start);
      expect(a.end, b.end);
    });

    test('across lines: one rect per line, partial first and last', () {
      final s = TextSelector.between(t, 1, 4)!; // quick … jumps
      expect(s.quote, 'quick brown fox jumps');
      expect(s.rects.length, 2);
      // Line 0 from "quick" to the end of "brown".
      expect(s.rects[0].x0, 96);
      expect(s.rects[0].x1, 72 + 15 * 6);
      // Line 1 from "fox" to the end of "jumps".
      expect(s.rects[1].x0, 72);
      expect(s.rects[1].x1, 72 + 9 * 6);
      expect(s.rects[1].y0, 114);
    });

    test('a span of three lines has a full middle line', () {
      final s = TextSelector.between(t, 1, 7)!;
      expect(s.rects.length, 3);
      expect(s.rects[1].x0, 72);
      expect(s.rects[1].x1, 72 + 14 * 6);
    });

    test('every row has the same height', () {
      final s = TextSelector.between(t, 0, 8)!;
      final heights = s.rects.map((r) => r.height).toSet();
      expect(heights.length, 1);
    });

    test('a range inside a word is clipped at character precision', () {
      // "quick" is chars 4..9; take "ui" = chars 5..7.
      final s = TextSelector.fromRange(t, 5, 7)!;
      expect(s.quote, 'ui');
      expect(s.rects.single.x0, 72 + 5 * 6);
      expect(s.rects.single.x1, 72 + 7 * 6);
    });

    test('a row of only hairline glyphs is still at least 6 pt tall', () {
      // A fraction bar: 0.5 pt tall.
      final p = PageText.build(
        Int32List.fromList([0x2212]),
        Float32List.fromList([72, 104.75, 90, 105.25]),
      );
      final s = TextSelector.between(p, 0, 0)!;
      expect(s.rects.single.height, TextSelector.minRowHeight);
      expect(s.rects.single.y0, closeTo(102, 0.01));
    });

    test('invalid inputs give null', () {
      expect(TextSelector.between(t, -1, 2), isNull);
      expect(TextSelector.between(t, 0, 99), isNull);
      expect(TextSelector.fromRange(t, 3, 3), isNull);
      expect(TextSelector.fromRange(t, 3, 4), isNull, reason: 'just a space');
    });

    test('a tall glyph does not make its row tall', () {
      // "ab ∫ cd": the integral sign is 36 pt tall.
      final codes = Int32List.fromList([
        ...'ab'.runes,
        0x20,
        0x222B,
        0x20,
        ...'cd'.runes,
      ]);
      final boxes = Float32List.fromList([
        72,
        100,
        78,
        110,
        78,
        100,
        84,
        110,
        84,
        100,
        90,
        110,
        90,
        90,
        98,
        126,
        98,
        100,
        104,
        110,
        104,
        100,
        110,
        110,
        110,
        100,
        116,
        110,
      ]);
      final p = PageText.build(codes, boxes);
      final s = TextSelector.between(p, 0, 2)!; // ab ∫ cd
      expect(s.rects.length, 1);
      expect(s.rects.single.y0, 100);
      expect(s.rects.single.y1, 110);
      final only = TextSelector.between(p, 1, 1)!; // the sign alone
      expect(only.rects.single.y0, 90);
      expect(only.rects.single.y1, 126);
    });
  });

  group('sentenceAt', () {
    String sentence(String text, String word) {
      final t = layout([text]);
      final w = [
        for (var i = 0; i < t.words.length; i++)
          if (t.quote(t.words[i].start, t.words[i].end) == word) i,
      ].first;
      return TextSelector.sentenceAt(t, w)!.quote;
    }

    test('takes the sentence around a word', () {
      const text = 'We map keys. Then we reduce values! Is it done? Yes.';
      expect(sentence(text, 'reduce'), 'Then we reduce values!');
      expect(sentence(text, 'map'), 'We map keys.');
      expect(sentence(text, 'done?'), 'Is it done?');
      expect(sentence(text, 'Yes.'), 'Yes.');
    });

    test('abbreviations and initials do not end a sentence', () {
      const text =
          'See Fig. 3 for details, e.g. the map step. Then J. Dean wrote it.';
      expect(
        sentence(text, 'details,'),
        'See Fig. 3 for details, e.g. the map step.',
      );
      expect(sentence(text, 'wrote'), 'Then J. Dean wrote it.');
    });

    test('a full stop before a lower-case word does not end it', () {
      const text = 'Version 2.0 of the tool. it was fast.';
      expect(sentence(text, 'tool.'), 'Version 2.0 of the tool. it was fast.');
    });

    test('closing quotes after the stop are allowed', () {
      const text = 'He said "go." Then he left.';
      expect(sentence(text, 'said'), 'He said "go."');
    });

    test('runs across lines', () {
      final t = layout(['This sentence runs', 'over two lines. Next one.']);
      final s = TextSelector.sentenceAt(t, 1)!;
      expect(s.quote, 'This sentence runs over two lines.');
      expect(s.rects.length, 2);
    });

    test('a heading without a stop does not join the paragraph below', () {
      final t = layout(
        [
          '2 Programming Model',
          'The computation takes keys.',
          'It then reduces them.',
        ],
        ys: [100, 126, 140],
      );
      final s = TextSelector.sentenceAt(t, 3)!; // "computation"
      expect(s.quote, 'The computation takes keys.');
    });

    test('a jump back up the page (a new column) ends the sentence', () {
      final t = layout(
        ['left column ends here', 'and right column starts'],
        ys: [300, 100],
      );
      expect(TextSelector.sentenceAt(t, 1)!.quote, 'left column ends here');
    });

    test('invalid word is null', () {
      final t = layout(['a b']);
      expect(TextSelector.sentenceAt(t, -1), isNull);
      expect(TextSelector.sentenceAt(t, 5), isNull);
    });
  });

  group('region', () {
    test('normalizes corners and carries the placeholder quote', () {
      final r = TextSelector.region(200, 300, 100, 150)!;
      expect(r.isRegion, isTrue);
      expect(r.quote, '(image region)');
      expect(r.rects.single.x0, 100);
      expect(r.rects.single.y0, 150);
      expect(r.rects.single.x1, 200);
      expect(r.rects.single.y1, 300);
      expect(r.start, -1);
    });

    test('a slip smaller than 4 pt is nothing', () {
      expect(TextSelector.region(10, 10, 12, 50), isNull);
      expect(TextSelector.region(10, 10, 50, 13), isNull);
    });
  });

  group('MarkDrag', () {
    final t = layout(['the quick brown', 'fox jumps over', 'the lazy dog']);

    test('a tap selects the word and nothing else', () {
      final d = MarkDrag(t, 100, 105);
      expect(d.isText, isTrue);
      expect(d.selection!.quote, 'quick');
    });

    test('dragging extends across lines to the word under the pointer', () {
      final d = MarkDrag(t, 100, 105); // quick
      final s = d.update(110, 120)!; // line 1, over "jumps" (x 102..132)
      expect(s.quote, 'quick brown fox jumps');
      expect(s.rects.length, 2);
    });

    test('dragging backwards works', () {
      final d = MarkDrag(t, 110, 120); // jumps
      final s = d.update(100, 105)!; // quick
      expect(s.quote, 'quick brown fox jumps');
    });

    test('dragging back to the start shrinks to one word', () {
      final d = MarkDrag(t, 100, 105);
      d.update(110, 120);
      expect(d.update(100, 105)!.quote, 'quick');
    });

    test('dragging into the margin extends to the line end', () {
      final d = MarkDrag(t, 80, 105); // the
      expect(d.update(550, 105)!.quote, 'the quick brown');
    });

    test('down on empty paper makes a rectangle', () {
      final d = MarkDrag(t, 400, 400);
      expect(d.isText, isFalse);
      expect(d.selection, isNull);
      expect(d.update(402, 402), isNull, reason: 'too small yet');
      final s = d.update(450, 460)!;
      expect(s.isRegion, isTrue);
      expect(s.rects.single.width, 50);
    });

    test('a page with no text always makes a rectangle', () {
      final d = MarkDrag(PageText.empty, 100, 100);
      expect(d.isText, isFalse);
      expect(d.update(160, 180)!.isRegion, isTrue);
    });

    test('tolerance decides whether a near miss grabs a word', () {
      expect(MarkDrag(t, 100, 94, tolerance: 8).isText, isTrue);
      expect(MarkDrag(t, 100, 94, tolerance: 2).isText, isFalse);
    });
  });
}
