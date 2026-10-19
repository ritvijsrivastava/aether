import 'dart:typed_data';

import 'package:aether/domain/text/page_text.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:flutter_test/flutter_test.dart';

/// SPEC §13: "Highlight drag-select on a text page: selection updates every
/// frame; hit-test under 1 ms". Run here on a page denser than any real one
/// (3,000 words, 60 lines), in a debug-mode VM, so passing here leaves a wide
/// margin on a device.
PageText densePage({int lines = 60, int wordsPerLine = 50}) {
  final codes = <int>[];
  final boxes = <double>[];
  for (var l = 0; l < lines; l++) {
    var x = 36.0;
    final y = 40.0 + l * 12;
    for (var w = 0; w < wordsPerLine; w++) {
      for (final r in 'word${w % 10}'.runes) {
        codes.add(r);
        boxes.addAll([x, y, x + 3.2, y + 9]);
        x += 3.2;
      }
      codes.add(0x20);
      boxes.addAll([x, y, x + 1.5, y + 9]);
      x += 1.5;
    }
    codes.add(0x0A);
    boxes.addAll([0, 0, 0, 0]);
  }
  return PageText.build(Int32List.fromList(codes), Float32List.fromList(boxes));
}

/// Average microseconds per call of [f] over [n] calls (after a warm-up).
double microsPerCall(int n, void Function(int i) f) {
  for (var i = 0; i < 200; i++) {
    f(i);
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    f(i);
  }
  return sw.elapsedMicroseconds / n;
}

void main() {
  final page = densePage();

  test('the dense page is as dense as claimed', () {
    expect(page.words.length, 3000);
    expect(page.lines.length, 60);
  });

  test('hit-testing a point takes well under 1 ms', () {
    final us = microsPerCall(3000, (i) {
      TextSelector.wordAt(page, 36 + (i * 7) % 550, 40 + (i * 13) % 700);
    });
    // ignore: avoid_print
    print('wordAt: ${us.toStringAsFixed(1)} µs');
    expect(us, lessThan(1000));
  });

  test('finding the word nearest a point takes well under 1 ms', () {
    final us = microsPerCall(3000, (i) {
      TextSelector.wordNear(page, (i * 11) % 700, (i * 17) % 800);
    });
    // ignore: avoid_print
    print('wordNear: ${us.toStringAsFixed(1)} µs');
    expect(us, lessThan(1000));
  });

  test(
    'extending a drag across the whole page, every frame, stays under 1 ms',
    () {
      final drag = MarkDrag(page, 40, 45);
      final us = microsPerCall(2000, (i) {
        // The pointer sweeps down and across the page; the selection grows to
        // thousands of characters and its rects are rebuilt on every update.
        drag.update(40 + (i * 3) % 520, 45 + (i * 5) % 700);
      });
      // ignore: avoid_print
      print('MarkDrag.update: ${us.toStringAsFixed(1)} µs');
      expect(us, lessThan(1000));
    },
  );

  test('a whole-page selection builds one rect per line, quickly', () {
    final sw = Stopwatch()..start();
    final sel = TextSelector.between(page, 0, page.words.length - 1)!;
    // ignore: avoid_print
    print('whole page selection: ${sw.elapsedMicroseconds} µs');
    expect(sel.rects.length, 60);
    expect(sw.elapsedMilliseconds, lessThan(20));
  });

  test('widening to a sentence, once per double tap, is also fast', () {
    final us = microsPerCall(100, (i) {
      TextSelector.sentenceAt(page, 1500);
    });
    // ignore: avoid_print
    print('sentenceAt: ${us.toStringAsFixed(1)} µs');
    expect(us, lessThan(16000), reason: 'well within one frame at 60 Hz');
  });
}
