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
  void clearPageInk() => log.add('page');
  @override
  void clearAllInk() => log.add('all');
  @override
  void clearBoard() => log.add('board');
}

/// A clock the tests move by hand.
class Clock {
  DateTime now = DateTime(2030);
  void advance(int ms) => now = now.add(Duration(milliseconds: ms));
  DateTime call() => now;
}

ProviderContainer container(Clock clock) {
  final c = ProviderContainer(
    overrides: [clockProvider.overrideWithValue(clock.call)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('pressTool', () {
    test(
      'a second press on the tool in use folds its panel, then opens it',
      () {
        final clock = Clock();
        final c = container(clock);
        final n = c.read(canvasUiProvider.notifier);
        n.pressTool(CanvasTool.ink);
        expect(c.read(canvasUiProvider).tool, CanvasTool.ink);
        expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
        clock.advance(150);
        n.pressTool(CanvasTool.ink);
        expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
        clock.advance(500); // too slow: a fresh first press
        n.pressTool(CanvasTool.ink);
        expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
        clock.advance(150); // quick again: opens
        n.pressTool(CanvasTool.ink);
        expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
      },
    );

    test('three quick presses are one double tap, not two', () {
      final clock = Clock();
      final c = container(clock);
      final n = c.read(canvasUiProvider.notifier);
      n.pressTool(CanvasTool.ink);
      clock.advance(100);
      n.pressTool(CanvasTool.ink);
      clock.advance(100);
      n.pressTool(CanvasTool.ink);
      expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
    });

    test('two slow presses do nothing but select', () {
      final clock = Clock();
      final c = container(clock);
      final n = c.read(canvasUiProvider.notifier);
      n.pressTool(CanvasTool.erase);
      clock.advance(600);
      n.pressTool(CanvasTool.erase);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
    });

    test('quick presses on different tools never fold anything', () {
      final clock = Clock();
      final c = container(clock);
      final n = c.read(canvasUiProvider.notifier);
      n.pressTool(CanvasTool.ink);
      clock.advance(50);
      n.pressTool(CanvasTool.erase);
      clock.advance(50);
      n.pressTool(CanvasTool.ink);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
      expect(c.read(canvasUiProvider).tool, CanvasTool.ink);
    });

    test('tools without options are never folded', () {
      final clock = Clock();
      final c = container(clock);
      final n = c.read(canvasUiProvider.notifier);
      n.pressTool(CanvasTool.pan);
      clock.advance(50);
      n.pressTool(CanvasTool.pan);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
      n.togglePanel(CanvasTool.note);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
    });

    test('each tool remembers its own fold', () {
      final c = container(Clock());
      final n = c.read(canvasUiProvider.notifier);
      n.setPanelCollapsed(CanvasTool.ink, true);
      n.setTool(CanvasTool.erase);
      expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
      n.setPanelCollapsed(CanvasTool.erase, true);
      n.setPanelCollapsed(CanvasTool.ink, false);
      expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.erase});
    });
  });

  group('gestureDone', () {
    test('folds the tool in use when auto-hide is on', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(canvasUiProvider.notifier)..setTool(CanvasTool.ink);
      n.gestureDone(CanvasTool.ink, autoHide: true);
      expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
    });

    test('does nothing when auto-hide is off, or for another tool', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(canvasUiProvider.notifier)..setTool(CanvasTool.ink);
      n.gestureDone(CanvasTool.ink, autoHide: false);
      n.gestureDone(CanvasTool.erase, autoHide: true);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
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

    testWidgets('Ink, Mark and Erase each show their own, one horizontal row', (
      tester,
    ) async {
      final c = await pump(tester, onClear: Clears());
      final n = c.read(canvasUiProvider.notifier);
      n.setTool(CanvasTool.ink);
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      final a = tester.getRect(find.byTooltip('Coral'));
      final b = tester.getRect(find.byTooltip('Blue'));
      expect(a.center.dy, b.center.dy, reason: 'colours side by side');
      expect(tester.getRect(find.byType(Slider)).center.dy, a.center.dy);
      n.setTool(CanvasTool.mark);
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      expect(find.byTooltip('Coral'), findsOneWidget);
      n.setTool(CanvasTool.erase);
      await tester.pump();
      expect(find.text('Erase part of a stroke'), findsOneWidget);
      expect(find.byTooltip('Coral'), findsNothing);
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

    testWidgets('Erase has Clear page ink, Clear all ink and Clear board', (
      tester,
    ) async {
      final clears = Clears();
      final c = await pump(tester, onClear: clears);
      c.read(canvasUiProvider.notifier).setTool(CanvasTool.erase);
      await tester.pump();
      await tester.tap(find.text('Clear page ink'));
      await tester.tap(find.text('Clear all ink'));
      await tester.tap(find.text('Clear board'));
      expect(clears.log, ['page', 'all', 'board']);
      for (final label in ['Clear page ink', 'Clear all ink', 'Clear board']) {
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
      for (final t in [CanvasTool.ink, CanvasTool.erase, CanvasTool.mark]) {
        n.setTool(t);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: t.label);
      }
    });
  });

  group('the tool rail', () {
    testWidgets('double-tapping the Ink button folds and reopens its panel', (
      tester,
    ) async {
      final clock = Clock();
      final c = container(clock);
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
      await tester.tap(find.text('Ink'));
      clock.advance(100);
      await tester.tap(find.text('Ink'));
      await tester.pump();
      expect(c.read(canvasUiProvider).collapsedPanels, {CanvasTool.ink});
      clock.advance(600);
      await tester.tap(find.text('Ink'));
      clock.advance(100);
      await tester.tap(find.text('Ink'));
      await tester.pump();
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
    });

    testWidgets('single taps just choose the tool', (tester) async {
      final clock = Clock();
      final c = container(clock);
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
      clock.advance(1000);
      await tester.tap(find.text('Ink'));
      await tester.pump();
      expect(c.read(canvasUiProvider).tool, CanvasTool.ink);
      expect(c.read(canvasUiProvider).collapsedPanels, isEmpty);
    });
  });
}
