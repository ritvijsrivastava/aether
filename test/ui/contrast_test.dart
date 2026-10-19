import 'dart:math';

import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double _lin(double c) =>
    c <= .03928 ? c / 12.92 : pow((c + .055) / 1.055, 2.4).toDouble();
double _lum(Color c) =>
    .2126 * _lin(c.r) + .7152 * _lin(c.g) + .0722 * _lin(c.b);

/// WCAG contrast of [fg] over [bg]; [fg] may be translucent.
double contrast(Color fg, Color bg) {
  final f = Color.alphaBlend(fg, bg);
  final a = _lum(f), b = _lum(bg);
  return (max(a, b) + .05) / (min(a, b) + .05);
}

void main() {
  for (final t in [AetherTokens.light, AetherTokens.dark]) {
    final name = t.isDark ? 'dark' : 'light';

    group('$name text meets AA (4.5:1)', () {
      final pairs = <String, (Color, Color)>{
        'ink on desk': (t.ink, t.desk),
        'ink on panel': (t.ink, t.panel),
        'ink on canvas': (t.ink, t.canvas),
        'muted on panel': (t.inkMuted, t.panel),
        'muted on desk': (t.inkMuted, t.desk),
        'faint on panel': (t.inkFaint, t.panel),
        'faint on desk': (t.inkFaint, t.desk),
        'onIndigo on indigo': (t.onIndigo, t.indigo),
        'onIndigo on indigoPressed': (t.onIndigo, t.indigoPressed),
        'indigoText on panel': (t.indigoText, t.panel),
        'indigoText on indigoWash': (t.indigoText, t.indigoWash),
        'desk on ink (selected chip)': (t.desk, t.ink),
        'danger on panel': (t.danger, t.panel),
        'ink on claim': (AetherTokens.onMark, AetherTokens.claim),
        'ink on method': (AetherTokens.onMark, AetherTokens.method),
        'ink on question': (AetherTokens.onMark, AetherTokens.question),
        'ink on note paper': (AetherTokens.onMark, AetherTokens.notePaper),
      };
      pairs.forEach((label, p) {
        test(
          label,
          () => expect(contrast(p.$1, p.$2), greaterThanOrEqualTo(4.5)),
        );
      });
    });

    group('$name non-text meets 3:1', () {
      test('indigo control against the panel', () {
        expect(contrast(t.indigo, t.panel), greaterThanOrEqualTo(3));
      });
      test('selection ring (ink) against the panel', () {
        expect(contrast(t.ink, t.panel), greaterThanOrEqualTo(3));
      });
      test('glyph ink on every meaning disc', () {
        for (final c in [
          AetherTokens.claim,
          AetherTokens.method,
          AetherTokens.question,
        ]) {
          expect(contrast(AetherTokens.onMark, c), greaterThanOrEqualTo(3));
        }
      });
    });
  }

  test('paper stays white-ish text surface in both themes', () {
    expect(AetherTokens.dark.paper, AetherTokens.light.paper);
  });

  test('meaning colours alone are NOT enough against the panel, which is why glyphs exist', () {
    // Documented finding: this must keep failing, or the glyph rule is moot.
    for (final c in [
      AetherTokens.claim,
      AetherTokens.method,
      AetherTokens.question,
    ]) {
      expect(contrast(c, AetherTokens.light.panel), lessThan(3));
    }
  });
}
