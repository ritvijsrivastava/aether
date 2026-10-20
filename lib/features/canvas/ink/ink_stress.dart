import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../domain/ink/ink_geometry.dart';
import '../../../domain/model/models.dart';

/// Test strokes for measuring a crowded page on a device. Built only with
/// `--dart-define=AETHER_STRESS_INK=<count>`, only in debug and profile
/// builds, and only held in memory: nothing is ever saved.
const int stressInkCount = int.fromEnvironment('AETHER_STRESS_INK');

bool get stressInkEnabled => stressInkCount > 0 && !kReleaseMode;

/// [count] strokes of about 40 samples scattered over a 600 x 800 page.
List<Ink> stressStrokes(String pageId, int count) {
  final r = math.Random(5);
  return [
    for (var i = 0; i < count; i++)
      () {
        final x = r.nextDouble() * 560, y = r.nextDouble() * 760;
        final s = Float32List(40 * 3);
        for (var k = 0; k < 40; k++) {
          s[k * 3] = x + k * 0.8;
          s[k * 3 + 1] = y + math.sin(k / 5) * 6;
          s[k * 3 + 2] = 0.3 + 0.4 * (k / 40);
        }
        return Ink(
          id: 'stress-$i',
          docId: 'stress',
          pageId: pageId,
          samples: InkGeometry.simplify(s, 0.15),
          width: 2.5,
          color: 0xFF2B2723,
        );
      }(),
  ];
}
