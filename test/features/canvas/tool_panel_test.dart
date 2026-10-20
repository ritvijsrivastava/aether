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
  void clearAllInk() => log.add('all');
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

  group('focus moves', () {
    testWidgets(
      'pressing the canvas folds the panel; the tool button brings it back',
      (tester) async {
        final c = container();
        tester.view.physicalSize = const Size(600, 800);
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
        final n = c.read(canvasUiProvider.notifier);
        n.setTool(CanvasTool.ink);
        n.canvasPressed(autoHide: true);
        await tester.pump();
        expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
        await tester.tap(find.text('Ink'));
        await tester.pump();
        expect(
          c.read(canvasUiProvider).collapsedPanels,
          isEmpty,
          reason: 'the icon brings it back',
        );
      },
    );

    test('a press on the canvas folds the panel of the tool in use', () {
      final c = container();
      final n = c.read(canvasUiProvider.notifier)..setTool(CanvasTool.ink);
      n.canvasPressed(autoHide: true);
      expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
      // With the setting off, nothing folds (the panel returns only through
      // the tool button or its tab, never by pressing the canvas).
      final other = container();
      other.read(canvasUiProvider.notifier)
        ..setTool(CanvasTool.ink)
        ..canvasPressed(autoHide: false);
      expect(other.read(canvasUiProvider).collapsedPanels, isEmpty);
    });

    test('a tool without options is left alone', () {
      final c = container();
      final n = c.read(canvasUiProvider.notifier)..setTool(CanvasTool.pan);
      n.canvasPressed(autoHide: true);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
    });

    test('a stroke or wipe folds it, too', () {
      final c = container();
      final n = c.read(canvasUiProvider.notifier)..setTool(CanvasTool.erase);
      n.gestureDone(CanvasTool.erase, autoHide: true);
      expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.erase});
    });
  });

  group('ToolPanel', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      EraseClearActions? onClear,
      bool compact = false,
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
                child: ToolPanel(compact: compact, onClear: onClear),
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
      expect(a.center.dx, b.center.dx, reason: 'colours in one column');
      expect(b.top, greaterThan(a.bottom - 1), reason: 'stacked downwards');
      final slider = tester.getRect(find.byType(Slider));
      expect(
        slider.top,
        greaterThan(b.bottom - 1),
        reason: 'size below colours',
      );
      n.setTool(CanvasTool.erase);
      await tester.pump();
      expect(find.text('Erase part of a stroke'), findsOneWidget);
      final sw = tester.getRect(find.byType(Switch));
      final clear = tester.getRect(find.text('Clear all ink'));
      expect(clear.top, greaterThan(sw.bottom - 1), reason: 'buttons under it');
    });

    testWidgets(
      'a folded panel leaves a small tab with the colour; tap opens',
      (tester) async {
        final c = await pump(tester);
        final n = c.read(canvasUiProvider.notifier)..setTool(CanvasTool.ink);
        await tester.pump();
        n.setPanelCollapsed(CanvasTool.ink, true);
        await tester.pump();
        expect(find.byType(Slider), findsNothing);
        final tab = find.byTooltip('Show Ink options (double-tap Ink)');
        expect(tab, findsOneWidget);
        final r = tester.getRect(tab);
        expect(r.height, greaterThanOrEqualTo(48));
        expect(r.width, lessThan(120), reason: 'it is a tab, not a panel');
        await tester.tap(tab);
        await tester.pump();
        expect(find.byType(Slider), findsOneWidget);
        expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
      },
    );

    testWidgets('the tab is named for screen readers', (tester) async {
      final h = tester.ensureSemantics();
      final c = await pump(tester);
      c.read(canvasUiProvider.notifier)
        ..setTool(CanvasTool.erase)
        ..setPanelCollapsed(CanvasTool.erase, true);
      await tester.pump();
      expect(find.bySemanticsLabel('Show Erase options'), findsOneWidget);
      h.dispose();
    });

    testWidgets('Erase has Clear all ink', (tester) async {
      final clears = Clears();
      final c = await pump(tester, onClear: clears);
      c.read(canvasUiProvider.notifier).setTool(CanvasTool.erase);
      await tester.pump();
      await tester.tap(find.text('Clear all ink'));
      expect(clears.log, ['all']);
      for (final label in ['Clear all ink']) {
        expect(
          tester
              .getSize(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(TextButton),
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
          reason: label,
        );
      }
    });

    testWidgets('on a phone the Erase and Ink panels fit 360 dp', (
      tester,
    ) async {
      final c = await pump(
        tester,
        compact: true,
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
