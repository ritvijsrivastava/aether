@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

// Goldens use whatever weights FontLoader resolves (see flutter_test_config);
// they verify layout, colour and shape, not exact type weight.
void main() {
  const shots = <String, (Size, String)>{
    'library_phone': (Size(360, 800), '/'),
    'canvas_phone': (Size(360, 800), '/doc/board'),
    'canvas_tablet': (Size(840, 600), '/doc/board'),
    'canvas_desktop': (Size(1280, 720), '/doc/board'),
    'settings_tablet': (Size(840, 600), '/settings'),
  };
  for (final entry in shots.entries) {
    for (final b in Brightness.values) {
      testWidgets('${entry.key} ${b.name}', (tester) async {
        await pumpApp(
          tester,
          size: entry.value.$1,
          location: entry.value.$2,
          brightness: b,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${entry.key}_${b.name}.png'),
        );
      });
    }
  }
}
