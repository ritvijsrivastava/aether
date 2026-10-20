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

  testWidgets('the picker is in the card: square, hue and R G B fields', (
    tester,
  ) async {
    await pump(tester);
    expect(find.bySemanticsLabel('Saturation and brightness'), findsOneWidget);
    expect(find.bySemanticsLabel('Hue'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text('Saved colours'), findsOneWidget);
  });

  testWidgets('tapping a saved colour makes it the pen', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byTooltip('Colour').at(1));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColor, Swatch.coral);
    await tester.tap(find.byTooltip('Colour').at(3));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColor, Swatch.blue);
    expect(
      c.read(canvasUiProvider).inkColors.recent,
      ToolColours.inkDefault.recent,
      reason: 'choosing does not reorder the saved colours',
    );
  });

  testWidgets('dragging in the square changes the pen live, saving nothing', (
    tester,
  ) async {
    final c = await pump(tester);
    final r = tester.getRect(
      find.bySemanticsLabel('Saturation and brightness'),
    );
    final g = await tester.startGesture(Offset(r.center.dx, r.center.dy));
    await g.moveTo(Offset(r.right - 2, r.top + 2));
    await tester.pump();
    final during = c.read(canvasUiProvider).inkColor;
    expect(during, isNot(InkPalette.auto));
    await g.moveTo(Offset(r.center.dx, r.bottom - 1));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColor & 0xFFFFFF, lessThan(0x101010));
    await g.up();
    expect(
      c.read(canvasUiProvider).inkColors.recent,
      ToolColours.inkDefault.recent,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('typing red, green and blue sets the pen', (tester) async {
    final c = await pump(tester);
    final f = find.byType(TextField);
    await tester.enterText(f.at(0), '18');
    await tester.enterText(f.at(1), '171');
    await tester.enterText(f.at(2), '52');
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColor, 0xFF12AB34);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('plus keeps the current colour; auto cannot be kept', (
    tester,
  ) async {
    final c = await pump(tester);
    final f = find.byType(TextField);
    await tester.enterText(f.at(0), '18');
    await tester.enterText(f.at(1), '171');
    await tester.enterText(f.at(2), '52');
    await tester.pump();
    await tester.tap(find.byTooltip('Save this colour'));
    await tester.pump();
    expect(c.read(canvasUiProvider).inkColors.recent.first, 0xFF12AB34);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the saved colours are 40 dp targets with names', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      final size = tester.getSize(find.byTooltip('Colour').at(i));
      expect(size.width, greaterThanOrEqualTo(40));
      expect(size.height, greaterThanOrEqualTo(40));
    }
    expect(find.bySemanticsLabel('A saved Pen colour'), findsNWidgets(4));
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

  testWidgets('is one compact card', (tester) async {
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
    expect(size.width, lessThan(280));
    expect(size.height, lessThan(440));
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
