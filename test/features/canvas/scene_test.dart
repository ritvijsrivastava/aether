import 'dart:ui';

import 'package:aether/features/canvas/engine/painters.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scene = Scene.column([
    const Size(100, 200),
    const Size(100, 200),
    const Size(100, 200),
  ], gap: 50);

  test('column lays cards top to bottom with the gap', () {
    expect(scene.cards.map((c) => c.rect.top), [0, 250, 500]);
    expect(scene.cards.map((c) => c.rect.left), [0, 0, 0]);
    expect(scene.bounds, const Rect.fromLTWH(0, 0, 100, 700));
  });

  test('mixed page widths are centred on one vertical axis', () {
    final mixed = Scene.column([
      const Size(600, 800),
      const Size(400, 500),
      const Size(800, 600),
    ]);
    expect(mixed.cards.map((c) => c.rect.center.dx), [400, 400, 400]);
    expect(mixed.cards[1].rect.left, 200);
    expect(mixed.bounds.width, 800);
  });

  test('an empty column has empty bounds', () {
    expect(Scene.column(const []).bounds, Rect.zero);
  });

  test('visible returns only cards that overlap the viewport', () {
    final ids = scene
        .visible(const Rect.fromLTWH(0, 260, 100, 100))
        .map((c) => c.id);
    expect(ids, ['page-1']);
    expect(scene.visible(const Rect.fromLTWH(0, -500, 100, 100)), isEmpty);
    expect(scene.visible(const Rect.fromLTWH(0, 0, 1000, 1000)).length, 3);
    // A viewport spanning the gap between two pages sees both.
    expect(scene.visible(const Rect.fromLTWH(0, 190, 100, 100)).length, 2);
  });

  test('nearest picks by centre', () {
    expect(scene.nearest(const Offset(50, 590))!.id, 'page-2');
    expect(scene.nearest(const Offset(0, -900))!.id, 'page-0');
    expect(const Scene([]).nearest(Offset.zero), isNull);
  });

  test('moving a card changes only that card', () {
    final moved = scene.withCardMoved('page-1', const Offset(10, 20));
    expect(moved.cards[1].rect.topLeft, const Offset(10, 270));
    expect(moved.cards[0].rect, scene.cards[0].rect);
    expect(
      scene.cards[1].rect.topLeft,
      const Offset(0, 250),
      reason: 'original is immutable',
    );
  });

  test('a 500-page scene answers visibility quickly', () {
    final big = Scene.column([
      for (var i = 0; i < 500; i++) const Size(612, 792),
    ]);
    final sw = Stopwatch()..start();
    var n = 0;
    for (var i = 0; i < 1000; i++) {
      n += big.visible(Rect.fromLTWH(0, i * 300.0, 1000, 2000)).length;
    }
    sw.stop();
    expect(n, greaterThan(0));
    // 1000 queries against 500 cards; generous bound, this is about the cost
    // of one frame's worth of work even if it ran every frame.
    expect(sw.elapsedMilliseconds, lessThan(200));
  });

  group('handle layout', () {
    const v = ViewState(x: 10, y: 100, zoom: 1);
    final card = scene.cards[0];

    test('the handle sits above the card top-left at constant screen size', () {
      final r1 = HandleLayout.rect(card, v, const Color(0xFF000000))!;
      final r2 = HandleLayout.rect(
        card,
        const ViewState(x: 10, y: 100, zoom: 2),
        const Color(0xFF000000),
      )!;
      expect(r1.left, 10);
      expect(r1.bottom, 100 - HandleLayout.gap);
      expect(r1.height, HandleLayout.height);
      expect(r2.height, HandleLayout.height);
      expect(r2.width, r1.width);
    });

    test('the hit area is 48 dp tall, larger than the visible handle', () {
      final hit = HandleLayout.hitRect(card, v)!;
      expect(hit.height, HandleLayout.hitHeight);
      expect(hit.contains(hit.center), isTrue);
    });

    test('tiny cards have no handle', () {
      expect(
        HandleLayout.rect(
          card,
          const ViewState(zoom: 0.2),
          const Color(0xFF000000),
        ),
        isNull,
      );
      expect(HandleLayout.hitRect(card, const ViewState(zoom: 0.2)), isNull);
    });
  });
}
