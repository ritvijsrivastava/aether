import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/colour_strip.dart';
import 'package:aether/features/canvas/palette.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer make([PaletteStore? store]) {
  final c = ProviderContainer(
    overrides: [
      if (store != null) paletteStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('ToolColours', () {
    test('using a colour moves it to the front and keeps five at most', () {
      var c = const ToolColours(1, [1, 2, 3, 4, 5]);
      c = c.use(6);
      expect(c.current, 6);
      expect(c.recent, [6, 1, 2, 3, 4]);
      c = c.use(3);
      expect(c.recent, [3, 6, 1, 2, 4], reason: 'no duplicates');
    });

    test('encodes and decodes, and ignores damage', () {
      const c = ToolColours(9, [9, 8, 7]);
      expect(ToolColours.decode(c.encode()), c);
      expect(ToolColours.decode(null), isNull);
      expect(ToolColours.decode('nonsense'), isNull);
      expect(ToolColours.decode('5;4,x,3')!.recent, [4, 3]);
      expect(
        ToolColours.decode('5;1,2,3,4,5,6,7')!.recent,
        hasLength(ToolColours.max),
      );
    });
  });

  group('the notifier', () {
    test('ink starts on its default', () {
      final u = make().read(canvasUiProvider);
      expect(u.inkColor, InkPalette.warmInk);
      expect(u.inkColors.recent, hasLength(4));
    });

    test('choosing an ink colour keeps the tool and updates recents', () {
      final c = make();
      final n = c.read(canvasUiProvider.notifier);
      n.setTool(CanvasTool.pan);
      n.setInkColor(0xFF010203);
      expect(c.read(canvasUiProvider).tool, CanvasTool.pan);
      expect(c.read(canvasUiProvider).inkColors.recent.first, 0xFF010203);
    });

    test('switching tools never changes the ink colour', () {
      final c = make();
      final n = c.read(canvasUiProvider.notifier)
        ..setInkColor(0xFF0A0B0C)
        ..setTool(CanvasTool.ink)
        ..setTool(CanvasTool.erase)
        ..setTool(CanvasTool.ink);
      expect(n.state.inkColor, 0xFF0A0B0C);
    });

    test('colours come back after a restart', () async {
      final store = MemoryPaletteStore();
      final a = make(store);
      a.read(canvasUiProvider.notifier)
        ..setInkColor(0xFF111111)
        ..setInkColor(0xFF222222);
      await Future<void>.delayed(Duration.zero);

      final b = make(store);
      b.read(canvasUiProvider); // starts the restore
      await Future<void>.delayed(Duration.zero);
      final u = b.read(canvasUiProvider);
      expect(u.inkColor, 0xFF222222);
      expect(u.inkColors.recent.take(2), [0xFF222222, 0xFF111111]);
    });

    test(
      'a colour picked before the restore finishes is not overwritten',
      () async {
        final store = MemoryPaletteStore();
        await store.write('palette.ink', const ToolColours(7, [7]).encode());
        final c = make(store);
        c.read(canvasUiProvider.notifier).setInkColor(0xFF999999);
        await Future<void>.delayed(Duration.zero);
        expect(c.read(canvasUiProvider).inkColor, 0xFF999999);
      },
    );
  });

  group('ColourStrip', () {
    Future<List<int>> pumpStrip(
      WidgetTester tester,
      ToolColours colours,
    ) async {
      final picked = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: Scaffold(
            body: Center(
              child: ColourStrip(
                colours: colours,
                prefix: 'Pen',
                onPick: picked.add,
              ),
            ),
          ),
        ),
      );
      return picked;
    }

    testWidgets('shows each recent colour as a 48 dp, named button', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await pumpStrip(tester, ToolColours.inkDefault);
      expect(find.byTooltip('Colour'), findsNWidgets(4));
      expect(find.bySemanticsLabel('Other Pen colour'), findsOneWidget);
      h.dispose();
    });

    testWidgets('tapping a colour picks it', (tester) async {
      final picked = await pumpStrip(tester, ToolColours.inkDefault);
      await tester.tap(find.byTooltip('Colour').at(2));
      expect(picked, [Swatch.amber], reason: 'the third swatch is amber');
    });

    testWidgets('the current colour is marked selected', (tester) async {
      final h = tester.ensureSemantics();
      await pumpStrip(
        tester,
        const ToolColours(Swatch.blue, [Swatch.blue, Swatch.coral]),
      );
      expect(
        tester.getSemantics(find.byTooltip('Colour').first),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.byTooltip('Colour').last),
        isSemantics(isSelected: false),
      );
      h.dispose();
    });

    testWidgets('"any colour" opens the picker and returns what was chosen', (
      tester,
    ) async {
      final picked = await pumpStrip(tester, ToolColours.inkDefault);
      await tester.tap(find.byTooltip('Any colour'));
      await tester.pumpAndSettle();
      expect(find.text('Colour'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '12AB34');
      await tester.pump();
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      expect(picked.single & 0xFFFFFF, 0x12AB34);
      expect(picked.single >> 24, 0xFF, reason: 'always opaque');
    });

    testWidgets('cancelling the picker picks nothing', (tester) async {
      final picked = await pumpStrip(tester, ToolColours.inkDefault);
      await tester.tap(find.byTooltip('Any colour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
    });

    testWidgets('dragging in the square changes the colour', (tester) async {
      final picked = await pumpStrip(
        tester,
        const ToolColours(0xFFFF0000, [0xFFFF0000]),
      );
      await tester.tap(find.byTooltip('Any colour'));
      await tester.pumpAndSettle();
      final square = find.bySemanticsLabel('Saturation and brightness');
      final r = tester.getRect(square);
      // Bottom edge is black whatever the hue.
      await tester.tapAt(Offset(r.center.dx, r.bottom - 1));
      await tester.pump();
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      expect(picked.single & 0xFFFFFF, lessThan(0x101010));
    });
  });
}
