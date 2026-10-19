import 'dart:ui';

import 'package:aether/features/canvas/engine/page_surface.dart';
import 'package:aether/features/canvas/engine/painters.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the frame protocol a surface is driven with.
class RecordingSurface implements PageSurface {
  final List<String> calls = [];
  PageViewInfo? lastInfo;

  @override
  Listenable? get repaint => null;
  @override
  String? get stats => null;
  @override
  void beginFrame() => calls.add('begin');
  @override
  void paint(Canvas canvas, Card card, PageViewInfo info) {
    calls.add('paint:${card.id}');
    lastInfo = info;
  }

  @override
  void endFrame() => calls.add('end');
}

void main() {
  final scene = ValueNotifier(
    Scene.column([
      const Size(100, 100),
      const Size(100, 100),
      const Size(100, 100),
    ], gap: 50),
  );

  CardsPainter painter(RecordingSurface s, ViewState v, {double dpr = 1}) =>
      CardsPainter(
        view: ValueNotifier(v),
        scene: scene,
        surface: s,
        tokens: AetherTokens.light,
        devicePixelRatio: dpr,
      );

  void run(CardsPainter p, Size size) =>
      p.paint(Canvas(PictureRecorder()), size);

  test(
    'a frame is begin, paint for each visible card, then end (and only then)',
    () {
      final s = RecordingSurface();
      run(
        painter(s, const ViewState()),
        const Size(300, 160),
      ); // sees pages 0 and 1
      expect(s.calls, ['begin', 'paint:page-0', 'paint:page-1', 'end']);
    },
  );

  test('endFrame is called even when no card is visible', () {
    final s = RecordingSurface();
    run(painter(s, const ViewState(y: -5000)), const Size(300, 160));
    expect(s.calls, [
      'begin',
      'end',
    ], reason: 'so a surface can cancel work for pages that left');
  });

  test('the surface sees the zoom, the visible world and the pixel ratio', () {
    final s = RecordingSurface();
    run(
      painter(s, const ViewState(x: 20, y: 10, zoom: 2), dpr: 2.625),
      const Size(400, 300),
    );
    expect(s.lastInfo!.zoom, 2);
    expect(s.lastInfo!.devicePixelRatio, 2.625);
    expect(s.lastInfo!.viewportWorld, const Rect.fromLTWH(-10, -5, 200, 150));
  });

  test('a painter with a different pixel ratio is not considered equal', () {
    final s = RecordingSurface();
    final a = painter(s, const ViewState());
    expect(a.shouldRepaint(painter(s, const ViewState(), dpr: 2)), isTrue);
  });
}
