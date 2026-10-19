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

  test('clamped lets you roam one screen beyond the content, no further', () {
    const viewport = Size(1000, 800);
    const content = Rect.fromLTWH(0, 0, 2000, 1000);
    // Far right and down: pushed back so the viewport only touches the content.
    final far = const ViewState(
      x: -50000,
      y: -50000,
      zoom: 1,
    ).clamped(viewport, content);
    final r = far.worldRect(viewport);
    expect(r.left, closeTo(content.right, 1e-9));
    expect(r.top, closeTo(content.bottom, 1e-9));
    // Far left and up: viewport sits one screen before the content.
    final near = const ViewState(
      x: 50000,
      y: 50000,
      zoom: 1,
    ).clamped(viewport, content);
    final n = near.worldRect(viewport);
    expect(n.right, closeTo(content.left, 1e-9));
    expect(n.bottom, closeTo(content.top, 1e-9));
    // Inside the allowed region nothing changes.
    const ok = ViewState(x: -100, y: -100, zoom: 1);
    expect(ok.clamped(viewport, content), ok);
  });

  test(
    'clamping is always satisfiable, even zoomed out far past the content',
    () {
      const viewport = Size(1000, 800);
      const content = Rect.fromLTWH(0, 0, 300, 300);
      for (final z in [0.2, 0.5, 1.0, 3.0]) {
        final v = ViewState(
          x: 1e6,
          y: -1e6,
          zoom: z,
        ).clamped(viewport, content);
        expect(v.x.isFinite && v.y.isFinite, isTrue);
        final rect = v.worldRect(viewport);
        expect(
          rect.right >= content.left - 1e-9 &&
              rect.left <= content.right + 1e-9,
          isTrue,
        );
      }
    },
  );

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
