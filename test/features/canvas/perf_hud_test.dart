import 'dart:ui';

import 'package:aether/app/providers.dart';
import 'package:aether/features/canvas/perf_hud.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

/// A frame that started at [startUs] and took [buildUs] + [rasterUs].
FrameTiming frame(int startUs, int buildUs, int rasterUs) => FrameTiming(
  vsyncStart: startUs,
  buildStart: startUs,
  buildFinish: startUs + buildUs,
  rasterStart: startUs + buildUs,
  rasterFinish: startUs + buildUs + rasterUs,
  rasterFinishWallTime: startUs + buildUs + rasterUs,
);

void main() {
  test('no frames gives empty stats', () {
    expect(FrameStatsCollector().stats.frames, 0);
  });

  test('averages build and raster, tracks the worst frame, derives fps', () {
    final c = FrameStatsCollector();
    // 60 fps cadence: a frame every 16 667 us; 2 ms build + 4 ms raster, one 30 ms hitch.
    c.add([
      for (var i = 0; i < 10; i++) frame(i * 16667, 2000, 4000),
      frame(10 * 16667, 10000, 20000),
    ]);
    final s = c.stats;
    expect(s.frames, 11);
    expect(s.worstMs, closeTo(30, 1e-9));
    expect(s.buildMs, closeTo((10 * 2 + 10) / 11, 1e-6));
    expect(s.rasterMs, closeTo((10 * 4 + 20) / 11, 1e-6));
    // First to last raster finish: 10 intervals of ~16.667 ms plus the long frame.
    expect(s.fps, inInclusiveRange(40, 62));
  });

  test('the window drops old frames', () {
    final c = FrameStatsCollector(window: 5);
    c.add([for (var i = 0; i < 20; i++) frame(i * 16667, 1000, 1000)]);
    expect(c.stats.frames, 5);
  });

  testWidgets('the overlay shows only when enabled in settings', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1280, 720), location: '/doc/board');
    expect(find.byType(PerfHud), findsNothing);
    await pumpApp(
      tester,
      size: const Size(1280, 720),
      location: '/doc/board',
      settings: const AppSettings(perfHud: true),
    );
    expect(find.byType(PerfHud), findsOneWidget);
    expect(find.textContaining('Hz'), findsOneWidget);
  });
}
