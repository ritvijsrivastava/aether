import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/erase/erase_options.dart';
import 'package:aether/features/canvas/tool_palette.dart';
import 'package:aether/features/canvas/tool_panel.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Clears implements EraseClearActions {
  final List<String> log = [];
  @override
  void clearAll() => log.add('all');
}

ProviderContainer container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('pressTool', () {
    test(
      'a press on the tool in use hides its options, another press shows them',
      () {
        final c = container();
        final n = c.read(canvasUiProvider.notifier);
        n.setTool(CanvasTool.ink);
        expect(c.read(canvasUiProvider).tool, CanvasTool.ink);
        expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
        n.pressTool(CanvasTool.ink);
        expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
        n.pressTool(CanvasTool.ink);
        expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
      },
    );

    test('tools without options are never folded', () {
      final c = container();
      final n = c.read(canvasUiProvider.notifier);
      n.pressTool(CanvasTool.pan);
      n.pressTool(CanvasTool.pan);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
      n.togglePanel(CanvasTool.select);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
    });

    test('choosing another tool shows its options and hides nothing else', () {
      final c = container();
      final n = c.read(canvasUiProvider.notifier);
      n.setTool(CanvasTool.ink);
      n.pressTool(CanvasTool.erase);
      expect(c.read(canvasUiProvider).tool, CanvasTool.erase);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
      // Fold erase, choose ink: erase stays folded, ink is open.
      n.pressTool(CanvasTool.erase);
      n.pressTool(CanvasTool.ink);
      expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.erase});
      n.pressTool(CanvasTool.erase);
      expect(
        c.read(canvasUiProvider).collapsedPanels,
        isEmpty,
        reason: 'choosing erase again shows its options',
      );
    });
  });

  group('ToolPanel', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      EraseClearActions? onClear,
      Size size = const Size(1000, 700),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(AetherTokens.light),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ToolPanel(onClear: onClear),
              ),
            ),
          ),
        ),
      );
      return c;
    }

    testWidgets('nothing for a tool without options', (tester) async {
      final c = await pump(tester);
      c.read(canvasUiProvider.notifier).setTool(CanvasTool.pan);
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('each option panel is a vertical column, its rows stacked', (
      tester,
    ) async {
      final c = await pump(tester, onClear: Clears());
      final n = c.read(canvasUiProvider.notifier);
      n.setTool(CanvasTool.ink);
      await tester.pump();
      final a = tester.getRect(find.byTooltip('Colour').at(0));
      final b = tester.getRect(find.byTooltip('Colour').at(3));
      expect(
        b.top,
        greaterThan(a.bottom - 1),
        reason: 'a second row of colours',
      );
      expect(
        a.center.dx,
        lessThan(b.center.dx + 1),
        reason: 'a grid, left to right',
      );
      final minus = tester.getRect(find.byTooltip('Thinner'));
      expect(
        minus.top,
        greaterThan(b.bottom - 1),
        reason: 'size below colours',
      );
      n.setTool(CanvasTool.erase);
      await tester.pump();
      expect(find.text('Erase part of a stroke'), findsOneWidget);
      final sw = tester.getRect(find.byType(Switch));
      final clear = tester.getRect(find.text('Clear all'));
      expect(clear.top, greaterThan(sw.bottom - 1), reason: 'buttons under it');
    });

    testWidgets('a hidden panel leaves nothing behind: no tab, no chevron', (
      tester,
    ) async {
      final c = await pump(tester, onClear: Clears());
      final n = c.read(canvasUiProvider.notifier)..setTool(CanvasTool.ink);
      await tester.pump();
      expect(find.byTooltip('Thinner'), findsOneWidget);
      n.setPanelCollapsed(CanvasTool.ink, true);
      await tester.pump();
      expect(find.byTooltip('Thinner'), findsNothing);
      expect(find.byType(InkResponse), findsNothing);
      n.togglePanel(CanvasTool.ink);
      await tester.pump();
      expect(find.byTooltip('Thinner'), findsOneWidget);
    });

    testWidgets('Clear all is a full-width row in the danger colour', (
      tester,
    ) async {
      final clears = Clears();
      final c = await pump(tester, onClear: clears);
      c.read(canvasUiProvider.notifier).setTool(CanvasTool.erase);
      await tester.pump();
      final label = find.text('Clear all');
      final colour = tester.widget<Text>(label).style!.color;
      expect(colour, AetherTokens.light.danger);
      final panel = tester.getRect(find.byType(EraseOptions));
      final row = tester.getRect(
        find.ancestor(of: label, matching: find.byType(InkWell)),
      );
      expect(row.width, panel.width, reason: 'the row spans the panel');
      expect(row.height, greaterThanOrEqualTo(48));
      // Anywhere on the row triggers it, not just the words.
      await tester.tapAt(Offset(row.right - 4, row.center.dy));
      expect(clears.log, ['all']);
    });

    testWidgets('on a phone the Erase and Ink panels fit 360 dp', (
      tester,
    ) async {
      final c = await pump(
        tester,
        onClear: Clears(),
        size: const Size(360, 640),
      );
      final n = c.read(canvasUiProvider.notifier);
      for (final t in [CanvasTool.ink, CanvasTool.erase, CanvasTool.select]) {
        n.setTool(t);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: t.label);
      }
    });
  });

  group('the tool rail', () {
    testWidgets(
      'tapping the tool in use hides its options; tapping again shows',
      (tester) async {
        final c = container();
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: buildTheme(AetherTokens.light),
              home: const Scaffold(body: ToolRail()),
            ),
          ),
        );
        c.read(canvasUiProvider.notifier).setTool(CanvasTool.erase);
        await tester.pump();
        await tester.tap(find.text('Erase'));
        await tester.pump();
        expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.erase});
        await tester.tap(find.text('Erase'));
        await tester.pump();
        expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
      },
    );

    testWidgets('taps choose the tool', (tester) async {
      final c = container();
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildTheme(AetherTokens.light),
            home: const Scaffold(body: ToolRail()),
          ),
        ),
      );
      await tester.tap(find.text('Erase'));
      await tester.pump();
      await tester.tap(find.text('Ink'));
      await tester.pump();
      expect(c.read(canvasUiProvider).tool, CanvasTool.ink);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
    });
  });
}
