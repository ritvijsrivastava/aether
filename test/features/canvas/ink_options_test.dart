import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/erase/erase_options.dart';
import 'package:aether/features/canvas/ink/ink_options.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
  testWidgets('starts on auto ink at 2.5', (tester) async {
    final c = await pump(tester);
    expect(c.read(canvasUiProvider).inkColor, InkPalette.auto);
    expect(c.read(canvasUiProvider).inkWidth, 2.5);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('tapping a colour chooses it', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byTooltip('Colour').at(1));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColor, Swatch.coral);
    await tester.tap(find.byTooltip('Colour').at(3));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColor, Swatch.blue);
  });

  testWidgets('the colour buttons are 48 dp targets with names', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      final size = tester.getSize(find.byTooltip('Colour').at(i));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(find.bySemanticsLabel('Other Pen colour'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('minus and plus change the pen size by half a dp', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(c.read(canvasUiProvider).inkWidth, 2.5);
    await tester.tap(find.byTooltip('Thicker'));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkWidth, 3.0);
    await tester.tap(find.byTooltip('Thinner'));
    await tester.pump();
    await tester.tap(find.byTooltip('Thinner'));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkWidth, 2.0);
  });

  testWidgets('the wave is drawn as thick as the pen', (tester) async {
    final c = await pump(tester);
    SizeWavePainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<SizeWavePainter>()
        .single;
    expect(painter().width, 2.5);
    c.read(canvasUiProvider.notifier).setInkWidth(6);
    await tester.pump();
    expect(painter().width, 6);
  });

  testWidgets('screen readers can raise and lower the size', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await pump(tester);
    final node = tester.getSemantics(find.bySemanticsLabel('Pen size 2.5'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.decrease), isTrue);
    handle.dispose();
    expect(c.read(canvasUiProvider).inkWidth, 2.5);
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

  testWidgets('is lean: a narrow, short card', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: const Scaffold(
            body: Align(alignment: Alignment.topLeft, child: InkOptions()),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(InkOptions));
    expect(size.width, lessThan(170));
    expect(size.height, lessThan(180));
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
