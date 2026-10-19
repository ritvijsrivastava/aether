import 'dart:ui';

import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';

CanvasController make({int pages = 5, Size viewport = const Size(1000, 800)}) {
  final c =
      CanvasController(
          scene: Scene.column([
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
    c.panEnd(const Offset(0, -2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final early = c.view.value.y;
    expect(early, lessThan(0));
    await tester.pump(const Duration(milliseconds: 100));
    final step1 = early - c.view.value.y;
    // 2000 px/s at drag 0.135 decays below 1 px/s after about 3.8 s.
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.isAnimating, isFalse);
    expect(c.view.value.y, lessThan(early));
    expect(
      c.view.value.y,
      greaterThan(-1500),
      reason: 'about 1000 px of travel in total',
    );
    expect(step1, greaterThan(0));
  });

  testWidgets('a fling into the edge stops at the edge', (tester) async {
    final c = make(pages: 2);
    c.setView(const ViewState());
    c.panEnd(const Offset(0, -30000));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.isAnimating, isFalse);
    final r = c.view.value.worldRect(c.viewport);
    expect(r.top, closeTo(c.scene.value.bounds.bottom, 1e-6));
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
      Scene.column([const Size(612, 792)]).cards[0].rect,
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

  group('refit on resize', () {
    testWidgets('an untouched first fit is redone when the screen grows', (
      tester,
    ) async {
      final c = make();
      c.viewport = const Size(1000, 500); // e.g. the soft keyboard still up
      c.fitFirst();
      final small = c.view.value.zoom;
      expect(c.refitOnResize, isTrue);

      c.viewport = const Size(1000, 800); // keyboard gone
      c.refitOnResize ? c.fitFirst() : c.setView(c.view.value);
      expect(c.view.value.zoom, greaterThan(small));
    });

    testWidgets('anything the user does stops it', (tester) async {
      for (final act in <String, void Function(CanvasController)>{
        'gesture': (c) => c.gestureStart(),
        'pan': (c) => c.panBy(const Offset(5, 5)),
        'zoom': (c) => c.zoomBy(1.25),
        'zoomTo': (c) => c.zoomTo(1),
        'fit page': (c) => c.fitPage(),
        'card drag': (c) => c.cardDragStart('page-0'),
      }.entries) {
        final c = make();
        c.fitFirst();
        expect(c.refitOnResize, isTrue, reason: act.key);
        act.value(c);
        // panBy alone is not a gesture start; the arbiter always calls
        // gestureStart first, which is what clears it.
        if (act.key == 'pan') c.gestureStart();
        expect(c.refitOnResize, isFalse, reason: act.key);
        await tester.pump(
          const Duration(seconds: 1),
        ); // let any animation finish
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('a restored view is not refit', (tester) async {
      final c = make();
      c.setView(const ViewState(x: -50, y: -60, zoom: 1.4));
      expect(c.refitOnResize, isFalse);
    });
  });

  group('reveal', () {
    // Page 2 (index 1) spans world x 0..612, y 872..1664.
    Offset centreOnScreen(CanvasController c, Rect world) =>
        c.view.value.worldToScreen(world.center);

    testWidgets('centres the target in the viewport', (tester) async {
      final c = make();
      c.setView(const ViewState(zoom: 1));
      const target = Rect.fromLTWH(100, 1000, 200, 20);
      c.reveal(target, animate: false);
      final s = centreOnScreen(c, target);
      expect(s.dx, closeTo(500, 1e-6));
      expect(s.dy, closeTo(400, 1e-6));
    });

    testWidgets('keeps a readable zoom as it is', (tester) async {
      final c = make();
      c.setView(const ViewState(zoom: 1.5));
      c.reveal(const Rect.fromLTWH(100, 1000, 200, 20), animate: false);
      expect(c.view.value.zoom, 1.5);
    });

    testWidgets('from far out, comes in to 100%', (tester) async {
      final c = make();
      c.setView(const ViewState(zoom: 0.3));
      c.reveal(const Rect.fromLTWH(100, 1000, 200, 20), animate: false);
      expect(c.view.value.zoom, 1.0);
    });

    testWidgets('a target wider than the screen is zoomed out to fit', (
      tester,
    ) async {
      final c = make();
      c.setView(const ViewState(zoom: 1));
      const wide = Rect.fromLTWH(0, 1000, 2000, 40);
      c.reveal(wide, animate: false);
      expect(c.view.value.zoom, closeTo(1000 * 0.85 / 2000, 1e-9));
      final r = c.view.value.worldRect(c.viewport);
      expect(r.left, lessThan(wide.left));
      expect(r.right, greaterThan(wide.right));
    });

    testWidgets('centres in the area the floating controls leave free', (
      tester,
    ) async {
      final c = make()..insets = const EdgeInsets.fromLTRB(100, 0, 0, 200);
      c.setView(const ViewState(zoom: 1));
      const target = Rect.fromLTWH(100, 1000, 200, 20);
      c.reveal(target, animate: false);
      final s = centreOnScreen(c, target);
      expect(s.dx, closeTo(100 + (1000 - 100) / 2, 1e-6));
      expect(s.dy, closeTo((800 - 200) / 2, 1e-6));
    });

    testWidgets('animated, it ends in the same place', (tester) async {
      final c = make();
      c.setView(const ViewState(zoom: 1));
      const target = Rect.fromLTWH(100, 1000, 200, 20);
      c.reveal(target);
      expect(c.isAnimating, isTrue);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final s = centreOnScreen(c, target);
      expect(s.dx, closeTo(500, 1e-3));
      expect(s.dy, closeTo(400, 1e-3));
    });

    testWidgets('does nothing before the canvas has a size', (tester) async {
      final c = make(viewport: Size.zero);
      final before = c.view.value;
      c.reveal(const Rect.fromLTWH(100, 1000, 200, 20), animate: false);
      expect(c.view.value, before);
    });
  });
}
