import 'dart:ui';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/marks/flash.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _flash = Flash('p0', [Box(20, 40, 80, 52)], Swatch.method);

/// 100 x 100 px at zoom 1, the page at the origin.
Future<ByteData> render(FlashController f) async {
  final recorder = PictureRecorder();
  FlashPainter(
    view: ValueNotifier(const ViewState()),
    scene: ValueNotifier(
      const Scene([
        Card(id: 'p0', index: 0, rect: Rect.fromLTWH(0, 0, 100, 100)),
      ]),
    ),
    flash: f,
    tokens: AetherTokens.light,
  ).paint(Canvas(recorder), const Size(100, 100));
  final image = await recorder.endRecording().toImage(100, 100);
  return (await image.toByteData())!;
}

int alphaAt(ByteData d, int x, int y) => d.getUint8((y * 100 + x) * 4 + 3);

void main() {
  testWidgets('shows for about a second and a half, then clears itself', (
    tester,
  ) async {
    final f = FlashController(tester);
    expect(f.current.value, isNull);
    f.show(_flash);
    expect(f.current.value, _flash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(f.current.value, _flash);
    await tester.pump(const Duration(milliseconds: 900));
    expect(f.current.value, isNull);
    f.dispose();
  });

  testWidgets('a second flash restarts the clock', (tester) async {
    final f = FlashController(tester);
    f.show(_flash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    f.show(const Flash('p0', [Box(0, 0, 10, 10)], Swatch.claim));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(f.current.value, isNotNull, reason: 'restarted, not the old timer');
    f.dispose();
  });

  testWidgets('draws an outline around the highlight that fades out', (
    tester,
  ) async {
    final f = FlashController(tester);
    await tester.runAsync(() async {
      expect(alphaAt(await render(f), 50, 40 - 3), 0, reason: 'nothing yet');
    });
    f.show(_flash);
    await tester.pump();
    late int early, late;
    await tester.runAsync(() async {
      // The outline sits 3 px outside the box: its centre line is at y = 37.
      early = alphaAt(await render(f), 50, 37);
    });
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.runAsync(() async {
      late = alphaAt(await render(f), 50, 37);
    });
    expect(early, greaterThan(150), reason: 'strong at the start');
    expect(late, lessThan(early), reason: 'fading');
    f.dispose();
  });

  testWidgets('with remove-animations it holds at full strength', (
    tester,
  ) async {
    final f = FlashController(tester)..reduceMotion = true;
    f.show(_flash);
    await tester.pump();
    late int early, mid;
    await tester.runAsync(() async {
      early = alphaAt(await render(f), 50, 37);
    });
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.runAsync(() async {
      mid = alphaAt(await render(f), 50, 37);
    });
    expect(mid, early);
    f.dispose();
  });

  testWidgets('a flash on a page that is gone paints nothing', (tester) async {
    final f = FlashController(tester);
    f.show(const Flash('missing', [Box(20, 40, 80, 52)], Swatch.claim));
    await tester.runAsync(() async {
      expect(alphaAt(await render(f), 50, 37), 0);
    });
    f.dispose();
  });
}
