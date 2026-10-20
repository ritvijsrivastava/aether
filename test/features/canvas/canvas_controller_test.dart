import 'dart:ui';

import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';

CanvasController make({Size viewport = const Size(1000, 800)}) {
  final c = CanvasController()
    ..attach(const TestVSync())
    ..viewport = viewport;
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets('panning is free: no edge, however far', (tester) async {
    final c = make();
    c.panBy(const Offset(1e7, -1e7));
    expect(c.view.value.x, 1e7);
    expect(c.view.value.y, -1e7);
  });

  testWidgets('zoomPan zooms about the anchor and stays in the zoom range', (
    tester,
  ) async {
    final c = make();
    c.setView(const ViewState(x: 100, y: 100));
    const anchor = Offset(500, 400);
    final before = c.view.value.screenToWorld(anchor);
    c.zoomPan(anchor: anchor, factor: 2, pan: Offset.zero);
    expect(c.view.value.zoom, 2);
    expect(
      (c.view.value.screenToWorld(anchor) - before).distance,
      lessThan(1e-9),
    );
    c.zoomPan(anchor: anchor, factor: 1e6, pan: Offset.zero);
    expect(c.view.value.zoom, ViewState.maxZoom);
  });

  testWidgets('fit with no content goes home: origin in the middle at 100%', (
    tester,
  ) async {
    final c = make();
    c.fit(animate: false);
    expect(c.view.value.zoom, 1);
    expect(c.view.value.worldToScreen(Offset.zero), const Offset(500, 400));
  });

  testWidgets('fit frames the content, centred in the free area', (
    tester,
  ) async {
    final c = make()
      ..insets = const EdgeInsets.only(left: 100)
      ..contentBounds = (() => const Rect.fromLTWH(5000, 5000, 400, 200));
    c.fit(animate: false);
    final centre = c.view.value.worldToScreen(const Offset(5200, 5100));
    expect(centre.dx, closeTo(100 + 900 / 2, 1e-6));
    expect(centre.dy, closeTo(400, 1e-6));
  });

  testWidgets('animated zoom reaches its target and stops', (tester) async {
    final c = make();
    c.setView(const ViewState());
    c.zoomBy(0.5);
    expect(c.isAnimating, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 16));
    expect(c.isAnimating, isFalse);
    expect(c.view.value.zoom, closeTo(0.5, 1e-6));
  });

  testWidgets('a new gesture interrupts an animation', (tester) async {
    final c = make();
    c.zoomBy(0.5);
    c.gestureStart();
    expect(c.isAnimating, isFalse);
  });

  testWidgets('a fling glides, slows down, and stops on its own', (
    tester,
  ) async {
    final c = make();
    c.panEnd(const Offset(0, -2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.view.value.y, lessThan(0));
    for (var i = 0; i < 1500; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.isAnimating, isFalse);
    expect(c.view.value.y, greaterThan(-1500));
  });

  testWidgets('a tiny release velocity does not start a fling', (tester) async {
    final c = make();
    c.panEnd(const Offset(10, 0));
    expect(c.isAnimating, isFalse);
  });
}
