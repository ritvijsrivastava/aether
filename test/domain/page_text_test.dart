import 'dart:typed_data';

import 'package:aether/domain/text/page_text.dart';
import 'package:aether/domain/text/page_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lays [lines] out like a page: 6 pt wide glyphs, 10 pt tall, 14 pt pitch,
/// spaces as real boxes, and a generated newline (zero box) between lines,
/// which is what pdfium reports.
PageText layout(List<String> lines, {bool newlines = true}) {
  final codes = <int>[];
  final boxes = <double>[];
  for (var l = 0; l < lines.length; l++) {
    final y = 100.0 + l * 14;
    var x = 72.0;
    for (final r in lines[l].runes) {
      codes.add(r);
      boxes.addAll([x, y, x + 6, y + 10]);
      x += 6;
    }
    if (newlines && l < lines.length - 1) {
      codes.add(0x0A);
      boxes.addAll([0, 0, 0, 0]);
    }
  }
  return PageText.build(Int32List.fromList(codes), Float32List.fromList(boxes));
}

void main() {
  group('words and lines', () {
    test('splits on spaces and groups into lines', () {
      final t = layout(['the quick brown', 'fox jumps']);
      expect(t.words.length, 5);
      expect(t.lines.length, 2);
      expect(t.lines[0].wordCount, 3);
      expect(t.lines[1].wordCount, 2);
      expect(t.words[0].start, 0);
      expect(t.words[0].end, 3);
      expect(t.words[0].box.x0, 72);
      expect(t.words[0].box.x1, 72 + 3 * 6);
    });

    test('word and line boxes are unions of the visible characters', () {
      final t = layout(['ab cd']);
      expect(t.words[1].box.x0, 72 + 3 * 6);
      expect(t.lines.single.box.x0, 72);
      expect(t.lines.single.box.x1, 72 + 5 * 6);
      expect(t.lines.single.box.y1, 110);
    });

    test('a character in a word maps to it; whitespace maps to none', () {
      final t = layout(['ab cd']);
      expect(t.wordAtChar(0), 0);
      expect(t.wordAtChar(1), 0);
      expect(t.wordAtChar(2), -1);
      expect(t.wordAtChar(3), 1);
      expect(t.wordAtChar(99), -1);
      expect(t.wordAtChar(-1), -1);
    });

    test('firstWordEndingAfter finds the word at or after a character', () {
      final t = layout(['ab cd ef']);
      expect(t.firstWordEndingAfter(0), 0);
      expect(t.firstWordEndingAfter(2), 1);
      expect(t.firstWordEndingAfter(5), 2);
      expect(t.firstWordEndingAfter(8), 3);
    });

    test('text with no space characters splits where there is a gap', () {
      // Two glyph runs 20 pt apart, no space character between them.
      final codes = Int32List.fromList([0x61, 0x62, 0x63, 0x64]);
      final boxes = Float32List.fromList([
        72, 100, 78, 110, //
        78, 100, 84, 110,
        104, 100, 110, 110,
        110, 100, 116, 110,
      ]);
      final t = PageText.build(codes, boxes);
      expect(t.words.map((w) => (w.start, w.end)), [(0, 2), (2, 4)]);
    });

    test('a jump back to a new line without a newline ends the word', () {
      final t = layout(['abc', 'def'], newlines: false);
      expect(t.words.length, 2);
      expect(t.lines.length, 2);
    });

    test('a superscript stays on its line', () {
      // "x" then a small raised "2" then " y".
      final codes = Int32List.fromList([0x78, 0x32, 0x20, 0x79]);
      final boxes = Float32List.fromList([
        72, 100, 78, 110, //
        78, 98, 82, 104, // raised, small
        82, 100, 85, 110,
        85, 100, 91, 110,
      ]);
      final t = PageText.build(codes, boxes);
      expect(t.lines.length, 1);
    });

    test('a tall glyph (integral sign) does not split its line', () {
      final codes = Int32List.fromList([0x61, 0x20, 0x222B, 0x20, 0x62]);
      final boxes = Float32List.fromList([
        72, 100, 78, 110, //
        78, 100, 84, 110,
        84, 94, 92, 118, // taller than the line either side
        92, 100, 98, 110,
        98, 100, 104, 110,
      ]);
      final t = PageText.build(codes, boxes);
      expect(t.lines.length, 1);
      expect(t.words.length, 3);
    });

    test('punctuation with a tiny box stays on its word and its line', () {
      // "pairs," where the comma's box is 2 pt high and hangs below the
      // x-height of the first word, as in real PDFs. Then " and".
      final codes = Int32List.fromList([
        ...'The'.runes,
        0x20,
        ...'ab,'.runes,
        0x20,
        ...'and'.runes,
      ]);
      final boxes = <double>[];
      void box(double x0, double y0, double x1, double y1) =>
          boxes.addAll([x0, y0, x1, y1]);
      for (var i = 0; i < 3; i++) {
        box(72.0 + i * 6, 100, 78.0 + i * 6, 107); // cap height only
      }
      box(90, 100, 96, 107); // space
      box(96, 100, 102, 109); // a
      box(102, 100, 108, 109); // b (has a descender)
      box(108.5, 106.8, 110, 109.2); // comma: tiny, low
      box(110, 100, 116, 109); // space
      for (var i = 0; i < 3; i++) {
        box(116.0 + i * 6, 100, 122.0 + i * 6, 107);
      }
      final t = PageText.build(codes, Float32List.fromList(boxes));
      expect(t.words.length, 3, reason: 'The, "ab,", and');
      expect(t.quote(0, t.length), 'The ab, and');
      expect(t.lines.length, 1);
    });

    test('lines a full leading apart are not merged by a tall glyph', () {
      final codes = Int32List.fromList([
        ...'ab'.runes,
        0x20,
        0x222B,
        0x20,
        ...'cd'.runes,
      ]);
      final boxes = Float32List.fromList([
        72, 100, 78, 110, 78, 100, 84, 110, //
        84, 100, 90, 110,
        90, 96, 98, 132, // very tall integral sign reaching into the next line
        98, 100, 104, 110,
        // next text line, 14 pt lower
        72, 114, 78, 124, 78, 114, 84, 124,
      ]);
      final t = PageText.build(codes, boxes);
      expect(t.lines.length, 2);
      expect(t.quote(0, t.length), 'ab \u222B cd');
    });

    test('an empty page has no words and hasText is false', () {
      expect(PageText.empty.words, isEmpty);
      expect(PageText.empty.hasText, isFalse);
      expect(PageText.empty.quote(0, 10), '');
    });

    test('a page of only whitespace has no text', () {
      final t = layout(['   ', '  ']);
      expect(t.hasText, isFalse);
    });

    test('invisible characters inside a word stay in its range', () {
      // a, generated zero-box char, b: one word spanning three characters.
      final codes = Int32List.fromList([0x61, 0xFFFD, 0x62]);
      final boxes = Float32List.fromList([
        72, 100, 78, 110, //
        0, 0, 0, 0,
        78, 100, 84, 110,
      ]);
      final t = PageText.build(codes, boxes);
      expect(t.words.length, 1);
      expect((t.words[0].start, t.words[0].end), (0, 3));
      expect(t.quote(0, 3), 'a\u{FFFD}b');
    });

    test('rejects a box array of the wrong size', () {
      expect(
        () => PageText.build(Int32List(2), Float32List(7)),
        throwsArgumentError,
      );
    });
  });

  group('quote', () {
    test('collapses whitespace and joins lines with one space', () {
      final t = layout(['the quick', 'brown  fox']);
      expect(t.quote(0, t.length), 'the quick brown fox');
    });

    test('clips to the requested range, mid-word', () {
      final t = layout(['hello world']);
      expect(t.quote(2, 8), 'llo wo');
    });

    test('an empty or reversed range is empty', () {
      final t = layout(['hello']);
      expect(t.quote(3, 3), '');
      expect(t.quote(4, 2), '');
    });

    test('clamps out-of-range indices', () {
      final t = layout(['hello']);
      expect(t.quote(-5, 99), 'hello');
    });

    test('de-hyphenates a word split across lines', () {
      final t = layout(['an inter-', 'national term']);
      expect(t.quote(0, t.length), 'an international term');
    });

    test('keeps the hyphen when the next line starts upper case', () {
      final t = layout(['the Kuhn-', 'Tucker conditions']);
      expect(t.quote(0, t.length), 'the Kuhn- Tucker conditions');
    });

    test('keeps a hyphen in the middle of a line', () {
      final t = layout(['a state-of-the-art', 'method']);
      expect(t.quote(0, t.length), 'a state-of-the-art method');
    });

    test('joins across pdfium\'s generated soft hyphen', () {
      // "inter" U+0002 newline "national": pdfium's own hyphenation marker.
      final codes = Int32List.fromList([
        ...'inter'.runes,
        0x02,
        0x0A,
        ...'national'.runes,
      ]);
      final boxes = Float32List(codes.length * 4);
      for (var i = 0; i < 5; i++) {
        boxes.setAll(i * 4, [72.0 + i * 6, 100, 78.0 + i * 6, 110]);
      }
      for (var i = 0; i < 8; i++) {
        boxes.setAll((7 + i) * 4, [72.0 + i * 6, 114, 78.0 + i * 6, 124]);
      }
      final t = PageText.build(codes, boxes);
      expect(t.words.length, 2);
      expect(t.quote(0, t.length), 'international');
    });

    test('expands ligatures', () {
      final t = layout(['\uFB01nd o\uFB03ce \uFB02ow']);
      expect(t.quote(0, t.length), 'find office flow');
    });

    test('handles characters outside the BMP as one character', () {
      final t = layout(['a \u{1D465} b']);
      expect(t.length, 5);
      expect(t.quote(0, t.length), 'a \u{1D465} b');
    });

    test('a range starting in whitespace begins at the next word', () {
      final t = layout(['ab cd']);
      expect(t.quote(2, 5), 'cd');
    });
  });

  group('context', () {
    test('returns the text on either side, capped at n characters', () {
      final t = layout(['alpha beta gamma delta epsilon zeta eta theta iota']);
      final s = t.quote(0, t.length).indexOf('gamma');
      final e = s + 'gamma'.length;
      // Context is normalized words: no leading or trailing space.
      expect(t.contextBefore(s, n: 8), 'pha beta');
      expect(t.contextAfter(e, n: 8), 'delta ep');
    });

    test('is shorter at the page edges', () {
      final t = layout(['alpha beta']);
      expect(t.contextBefore(0), '');
      expect(t.contextAfter(t.length), '');
      expect(t.contextBefore(6), 'alpha');
    });
  });

  group('codec', () {
    test('round-trips characters and boxes', () {
      final t = layout(['the quick', 'brown fox']);
      final back = PageTextCodec.decode(PageTextCodec.encode(t))!;
      expect(back.codes, t.codes);
      expect(back.boxes, t.boxes);
      expect(back.words.length, t.words.length);
      expect(back.quote(0, back.length), t.quote(0, t.length));
    });

    test('round-trips an empty page', () {
      final back = PageTextCodec.decode(PageTextCodec.encode(PageText.empty))!;
      expect(back.length, 0);
    });

    test('rejects garbage, truncation, and another version', () {
      final good = PageTextCodec.encode(layout(['abc']));
      expect(PageTextCodec.decode(Uint8List(0)), isNull);
      expect(
        PageTextCodec.decode(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
        isNull,
      );
      expect(
        PageTextCodec.decode(Uint8List.sublistView(good, 0, good.length - 1)),
        isNull,
      );
      final other = Uint8List.fromList(good)..[3] = 99;
      expect(PageTextCodec.decode(other), isNull);
    });
  });
}
