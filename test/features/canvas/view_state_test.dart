import 'dart:math';
import 'dart:ui';

import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screen/world conversion round-trips exactly', () {
    const v = ViewState(x: 110, y: -40, zoom: 0.8);
    for (final p in const [Offset.zero, Offset(300, 250), Offset(-12, 999)]) {
      final back = v.worldToScreen(v.screenToWorld(p));
      expect((back - p).distance, lessThan(1e-9));
    }
  });

  test('zoomAt keeps the world point under the anchor fixed (random)', () {
    final rnd = Random(1);
    for (var i = 0; i < 500; i++) {
      final v = ViewState(
        x: rnd.nextDouble() * 800 - 400,
        y: rnd.nextDouble() * 800 - 400,
        zoom: 0.25 + rnd.nextDouble() * 2.5,
      );
      final a = Offset(rnd.nextDouble() * 1000, rnd.nextDouble() * 700);
      final before = v.screenToWorld(a);
      final z = v.zoomAt(a, 0.5 + rnd.nextDouble() * 1.5);
      expect((z.screenToWorld(a) - before).distance, lessThan(1e-6));
    }
  });

  test('zoom is limited to 20% to 300%', () {
    const v = ViewState();
    expect(v.zoomAt(Offset.zero, 100).zoom, ViewState.maxZoom);
    expect(v.zoomAt(Offset.zero, 0.001).zoom, ViewState.minZoom);
  });

  test('the view is never clamped: any distance from the origin is fine', () {
    const far = ViewState(x: -1e9, y: 1e9, zoom: 2);
    final back = far.screenToWorld(far.worldToScreen(const Offset(5, 7)));
    expect(back.dx, closeTo(5, 1e-3));
    expect(far.panBy(const Offset(1e6, 1e6)).x, -1e9 + 1e6);
  });

  test('fitRect centres the target in the area left after insets', () {
    const viewport = Size(1280, 720);
    const insets = EdgeInsets.only(left: 88);
    const page = Rect.fromLTWH(200, 100, 612, 792);
    final v = ViewState.fitRect(page, viewport, insets: insets);
    final centre = v.worldToScreen(page.center);
    expect(centre.dx, closeTo(88 + (1280 - 88) / 2, 1e-9));
    expect(centre.dy, closeTo(360, 1e-9));
    // The whole page fits inside the visible area.
    final screen = Rect.fromPoints(
      v.worldToScreen(page.topLeft),
      v.worldToScreen(page.bottomRight),
    );
    expect(
      screen.left >= 88 &&
          screen.right <= 1280 &&
          screen.top >= 0 &&
          screen.bottom <= 720,
      isTrue,
    );
  });

  test('fitRect never zooms in past 100% by default', () {
    final v = ViewState.fitRect(
      const Rect.fromLTWH(0, 0, 50, 50),
      const Size(1000, 800),
    );
    expect(v.zoom, 1.0);
  });

  test('lerp interpolates zoom geometrically', () {
    final mid = ViewState.lerp(
      const ViewState(zoom: 0.25),
      const ViewState(zoom: 1.0),
      0.5,
    );
    expect(mid.zoom, closeTo(0.5, 1e-9));
  });
}
