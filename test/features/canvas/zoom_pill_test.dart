import 'package:aether/features/canvas/zoom_pill.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester, {double zoom = 1.5}) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AetherTokens.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: ZoomPill(
              zoom: zoom,
              onZoomIn: () => log.add('in'),
              onZoomOut: () => log.add('out'),
              onFit: () => log.add('fit'),
              openFor: const Duration(seconds: 2),
            ),
          ),
        ),
      ),
    );
    return log;
  }

  testWidgets('rests as just the zoom level', (tester) async {
    await pump(tester);
    expect(find.text('150%'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsNothing);
    expect(find.text('Fit'), findsNothing);
  });

  testWidgets('opens sideways to the left, anchored at its right edge', (
    tester,
  ) async {
    await pump(tester);
    final before = tester.getRect(find.byType(ZoomPill));
    await tester.tap(find.text('150%'));
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byType(ZoomPill));
    expect(after.right, before.right);
    expect(after.width, greaterThan(before.width));
    expect(after.height, before.height, reason: 'it grows sideways only');
    for (final t in ['Zoom out', 'Zoom in']) {
      expect(find.byTooltip(t), findsOneWidget);
    }
    expect(find.text('Fit'), findsOneWidget);
  });

  testWidgets('its buttons act, and tapping the level folds it', (
    tester,
  ) async {
    final log = await pump(tester);
    await tester.tap(find.text('150%'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.tap(find.text('Fit'));
    expect(log, ['in', 'out', 'fit']);
    await tester.tap(find.text('150%'));
    await tester.pumpAndSettle();
    expect(find.text('Fit'), findsNothing);
  });

  testWidgets('folds by itself after a quiet while', (tester) async {
    await pump(tester);
    await tester.tap(find.text('150%'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Fit'), findsNothing);
  });
}
