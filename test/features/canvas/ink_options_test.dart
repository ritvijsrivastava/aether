import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/erase/erase_options.dart';
import 'package:aether/features/canvas/ink/ink_options.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> pump(
  WidgetTester tester, {
  double width = 700,
}) async {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildTheme(AetherTokens.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: const InkOptions()),
          ),
        ),
      ),
    ),
  );
  return c;
}

void main() {
  testWidgets('starts on Warm Ink at 2.5', (tester) async {
    final c = await pump(tester);
    expect(c.read(canvasUiProvider).inkColor, InkPalette.warmInk);
    expect(c.read(canvasUiProvider).inkWidth, 2.5);
    expect(find.text('2.5'), findsOneWidget);
  });

  testWidgets('tapping a colour chooses it', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byTooltip('Coral'));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColor, Swatch.coral);
    await tester.tap(find.byTooltip('Blue'));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColor, Swatch.blue);
  });

  testWidgets('the colour buttons are 48 dp targets with names', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    for (final name in [
      'Warm ink'.replaceAll('Warm ink', 'Black'),
      'Coral',
      'Amber',
      'Blue',
    ]) {
      final size = tester.getSize(find.byTooltip(name));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Pen colour $name'), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets('the slider sets the pen size between 1 and 8', (tester) async {
    final c = await pump(tester);
    final slider = find.byType(Slider);
    final box = tester.getRect(slider);
    await tester.tapAt(Offset(box.left + 4, box.center.dy));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkWidth, lessThan(1.6));
    await tester.tapAt(Offset(box.right - 4, box.center.dy));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkWidth, greaterThan(7.4));
    expect(c.read(canvasUiProvider).inkWidth, lessThanOrEqualTo(8));
  });

  testWidgets('the size is clamped to the allowed range', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(canvasUiProvider.notifier);
    n.setInkWidth(50);
    expect(c.read(canvasUiProvider).inkWidth, 8);
    n.setInkWidth(0);
    expect(c.read(canvasUiProvider).inkWidth, 1);
  });

  testWidgets('fits a phone: 360 dp wide with the short slider', (
    tester,
  ) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: const Scaffold(
            body: Center(child: InkOptions(sliderWidth: 80, compact: true)),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(InkOptions)).width,
      lessThanOrEqualTo(360),
    );
  });

  testWidgets(
    'erase options: partial erase is off, and the switch turns it on',
    (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(AetherTokens.light),
            home: const Scaffold(body: Center(child: EraseOptions())),
          ),
        ),
      );
      expect(c.read(canvasUiProvider).erasePartial, isFalse);
      expect(find.text('Erase part of a stroke'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(c.read(canvasUiProvider).erasePartial, isTrue);
      final size = tester.getSize(find.byType(Switch));
      expect(size.height, greaterThanOrEqualTo(40));
    },
  );
}
