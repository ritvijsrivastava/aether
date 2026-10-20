import 'package:aether/features/canvas/canvas_pill.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool canUndo = false,
    bool canRedo = false,
    VoidCallback? onUndo,
    String title = 'Sketch',
    Size size = const Size(800, 600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: buildTheme(AetherTokens.light),
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: CanvasPill(
                    title: title,
                    canUndo: canUndo,
                    canRedo: canRedo,
                    onUndo: onUndo,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double opacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('shows the name and the four buttons', (tester) async {
    await pump(tester);
    expect(find.text('Sketch'), findsOneWidget);
    for (final tip in ['Back to library', 'Undo', 'Redo', 'Settings']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
  });

  testWidgets('rests faint and comes up under the mouse', (tester) async {
    await pump(tester);
    expect(opacity(tester), lessThan(1));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Sketch')));
    await tester.pump();
    expect(opacity(tester), 1);
    await mouse.moveTo(const Offset(700, 500));
    await tester.pump();
    expect(opacity(tester), lessThan(1));
  });

  testWidgets('comes up on a touch', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(tester.getCenter(find.text('Sketch')));
    await tester.pump();
    expect(opacity(tester), 1);
    await g.up();
  });

  testWidgets('Undo is disabled until there is something to undo', (
    tester,
  ) async {
    var undone = 0;
    await pump(tester, onUndo: () => undone++);
    await tester.tap(find.byTooltip('Undo'));
    expect(undone, 0);
    await pump(tester, canUndo: true, onUndo: () => undone++);
    await tester.tap(find.byTooltip('Undo'));
    expect(undone, 1);
  });

  testWidgets('a long name is cut, and the pill fits a phone', (tester) async {
    await pump(
      tester,
      title: 'A very long board name that would run on and on forever',
      size: const Size(360, 640),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(CanvasPill)).width,
      lessThanOrEqualTo(360),
    );
  });
}
