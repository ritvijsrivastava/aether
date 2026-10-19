import 'dart:ui';

import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';

CanvasController make({int pages = 5, Size viewport = const Size(1000, 800)}) {
  final c =
      CanvasController(
          scene: Scene.row([
            for (var i = 0; i < pages; i++) const Size(612, 792),
          ]),
        )
        ..attach(const TestVSync())
        ..viewport = viewport;
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets('panning is clamped to one screen beyond the cards', (
    tester,
  ) async {
    final c = make();
    c.setView(const ViewState());
    c.panBy(const Offset(1e6, 1e6));
    final r = c.view.value.worldRect(c.viewport);
    expect(r.right, closeTo(c.scene.value.bounds.left, 1e-6));
    expect(r.bottom, closeTo(c.scene.value.bounds.top, 1e-6));
  });

  testWidgets(
    'zoomPan zooms about the anchor and never leaves the allowed range',
    (tester) async {
      final c = make();
      c.setView(const ViewState(x: 100, y: 100));
      final anchor = const Offset(500, 400);
      final before = c.view.value.screenToWorld(anchor);
      c.zoomPan(anchor: anchor, factor: 1.5, pan: Offset.zero);
      expect(
        (c.view.value.screenToWorld(anchor) - before).distance,
        lessThan(1e-6),
      );
      c.zoomPan(anchor: anchor, factor: 1000, pan: Offset.zero);
      expect(c.view.value.zoom, ViewState.maxZoom);
    },
  );

  testWidgets('fitFirst shows the whole first page in the free area', (
    tester,
  ) async {
    final c = make();
    c.insets = const EdgeInsets.only(left: 88);
    c.fitFirst();
    final page = c.scene.value.cards.first.rect;
    final tl = c.view.value.worldToScreen(page.topLeft);
    final br = c.view.value.worldToScreen(page.bottomRight);
    expect(tl.dx >= 88 && br.dx <= 1000 && tl.dy >= 0 && br.dy <= 800, isTrue);
  });

  testWidgets('fitPage picks the page nearest the centre of the screen', (
    tester,
  ) async {
    final c = make();
    c.fitFirst();
    // Pan so page 3 is centred, then fit.
    final p3 = c.scene.value.cards[2].rect;
    c.setView(ViewState(x: 500 - p3.center.dx, y: 400 - p3.center.dy, zoom: 1));
    c.fitPage(animate: false);
    final centre = c.view.value.worldToScreen(p3.center);
    expect((centre - const Offset(500, 400)).distance, lessThan(1));
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
    c.setView(const ViewState());
    c.zoomBy(0.5);
    c.gestureStart();
    expect(c.isAnimating, isFalse);
  });

  testWidgets('a fling glides, slows down, and stops on its own', (
    tester,
  ) async {
    final c = make(pages: 20);
    c.setView(const ViewState(x: 0, y: 0));
    c.panEnd(const Offset(-2000, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final early = c.view.value.x;
    expect(early, lessThan(0));
    await tester.pump(const Duration(milliseconds: 100));
    final step1 = early - c.view.value.x;
    // 2000 px/s at drag 0.135 decays below 1 px/s after about 3.8 s.
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.isAnimating, isFalse);
    expect(c.view.value.x, lessThan(early));
    expect(
      c.view.value.x,
      greaterThan(-1500),
      reason: 'about 1000 px of travel in total',
    );
    expect(step1, greaterThan(0));
  });

  testWidgets('a fling into the edge stops at the edge', (tester) async {
    final c = make(pages: 2);
    c.setView(const ViewState());
    c.panEnd(const Offset(-30000, 0));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.isAnimating, isFalse);
    final r = c.view.value.worldRect(c.viewport);
    expect(r.left, closeTo(c.scene.value.bounds.right, 1e-6));
  });

  testWidgets('a tiny release velocity does not start a fling', (tester) async {
    final c = make();
    c.panEnd(const Offset(10, 0));
    expect(c.isAnimating, isFalse);
  });

  testWidgets('dragging a card moves it in world units and reports the total', (
    tester,
  ) async {
    final c = make();
    c.setView(const ViewState(zoom: 0.5));
    String? movedId;
    Offset? moved;
    c.onCardMoved = (id, d) {
      movedId = id;
      moved = d;
    };
    final before = c.scene.value.cards[1].rect;
    c.cardDragStart('page-1');
    c.cardDragBy(const Offset(50, 20));
    c.cardDragBy(const Offset(50, 0));
    c.cardDragEnd();
    final after = c.scene.value.cards[1].rect;
    expect(
      after.left - before.left,
      closeTo(200, 1e-9),
    ); // 100 screen px at 0.5x
    expect(after.top - before.top, closeTo(40, 1e-9));
    expect(movedId, 'page-1');
    expect(moved, const Offset(200, 40));
    // Other cards are untouched.
    expect(
      c.scene.value.cards[0].rect,
      Scene.row([const Size(612, 792)]).cards[0].rect,
    );
  });

  testWidgets('a drag that never moved reports nothing', (tester) async {
    final c = make();
    var called = false;
    c.onCardMoved = (_, _) => called = true;
    c.cardDragStart('page-0');
    c.cardDragEnd();
    expect(called, isFalse);
  });

  testWidgets('the scene bounds follow a moved card, so the clamp does too', (
    tester,
  ) async {
    final c = make(pages: 1);
    c.cardDragStart('page-0');
    c.cardDragBy(const Offset(5000, 0));
    c.cardDragEnd();
    expect(c.scene.value.bounds.left, 5000);
  });
}
