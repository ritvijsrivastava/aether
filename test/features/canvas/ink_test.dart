import 'dart:ui';

import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:aether/features/canvas/ink/ink_tool.dart';
import 'package:aether/features/canvas/input/pen_config.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List samples(List<(double, double, double)> pts) =>
    Float32List.fromList([
      for (final (x, y, p) in pts) ...[x, y, p],
    ]);

Ink ink(
  String id,
  String? page,
  List<(double, double, double)> pts, {
  double width = 4,
  int color = 0xFF000000,
}) => Ink(
  id: id,
  docId: 'd',
  pageId: page,
  samples: samples(pts),
  width: width,
  color: color,
);

class FakeInkSink implements InkSink {
  final List<({String? pageId, Float32List samples, double width, int color})>
  strokes = [];
  @override
  String addInk({
    String? pageId,
    required Float32List samples,
    required double width,
    required int color,
  }) {
    strokes.add((pageId: pageId, samples: samples, width: width, color: color));
    return 's${strokes.length}';
  }
}

ToolPoint pt(double x, double y, {double? pressure, int ms = 0}) => ToolPoint(
  position: Offset(x, y),
  time: Duration(milliseconds: ms),
  kind: PointerDeviceKind.stylus,
  pressure: pressure,
);

void main() {
  group('InkLayer', () {
    test('keeps strokes by page and in canvas space, and tells listeners', () {
      final layer = InkLayer();
      var changes = 0;
      layer.addListener(() => changes++);
      layer.add(ink('a', 'p0', [(10, 10, 1), (50, 10, 1)]));
      layer.add(ink('b', 'p0', [(10, 20, 1), (50, 20, 1)]));
      layer.add(ink('c', 'p1', [(0, 0, 1), (5, 5, 1)]));
      layer.add(ink('free', null, [(100, 100, 1), (200, 100, 1)]));
      expect(changes, 4);
      expect(layer.count, 4);
      expect(layer.forPage('p0').map((i) => i.id), ['a', 'b']);
      expect(layer.forPage('p1').length, 1);
      expect(layer.forPage(null).single.id, 'free');
      expect(layer.forPage('nope'), isEmpty);
    });

    test('knows how far each page\'s ink reaches, even past the page', () {
      final layer = InkLayer()
        ..add(ink('a', 'p0', [(10, 10, 1), (50, 10, 1)], width: 4))
        ..add(ink('b', 'p0', [(700, 900, 1), (710, 905, 1)], width: 4));
      final b = layer.boundsOf('p0')!;
      expect([b.x0, b.y0], [8, 8]);
      expect([b.x1, b.y1], [712, 907]);
      expect(layer.boundsOf('p9'), isNull);
    });

    test('remove forgets a stroke and shrinks the reach', () {
      final layer = InkLayer()
        ..add(ink('a', 'p0', [(10, 10, 1), (50, 10, 1)]))
        ..add(ink('b', 'p0', [(700, 900, 1), (710, 905, 1)]));
      layer.remove('b');
      layer.remove('b'); // twice is fine
      expect(layer.boundsOf('p0')!.x1, lessThan(100));
      layer.remove('a');
      expect(layer.boundsOf('p0'), isNull);
      expect(layer.count, 0);
    });

    test('replaceAll swaps everything at once', () {
      final layer = InkLayer()..add(ink('a', 'p0', [(1, 1, 1), (2, 2, 1)]));
      layer.replaceAll([
        ink('x', 'p1', [(1, 1, 1), (9, 9, 1)]),
      ]);
      expect(layer.forPage('p0'), isEmpty);
      expect(layer.byId('x'), isNotNull);
    });

    test('a page picture is recorded once, not on every paint', () {
      final layer = InkLayer()..add(ink('a', 'p0', [(10, 10, 1), (50, 10, 1)]));
      final rec = PictureRecorder();
      final c = Canvas(rec);
      for (var i = 0; i < 20; i++) {
        layer.paint(c, 'p0');
      }
      expect(layer.rebuilds, 1);
      rec.endRecording().dispose();
    });

    test('a new stroke is drawn on top of the picture, not a rebuild', () {
      final layer = InkLayer()..add(ink('a', 'p0', [(10, 10, 1), (50, 10, 1)]));
      final c = Canvas(PictureRecorder());
      layer.paint(c, 'p0');
      for (var i = 0; i < InkLayer.foldAfter; i++) {
        layer.add(ink('n$i', 'p0', [(10, 30.0 + i, 1), (50, 30.0 + i, 1)]));
        layer.paint(c, 'p0');
      }
      expect(layer.rebuilds, 1, reason: 'up to the fold limit, no rebuild');
      layer.add(ink('one-more', 'p0', [(10, 99, 1), (50, 99, 1)]));
      layer.paint(c, 'p0');
      expect(layer.rebuilds, 2, reason: 'then they are folded in');
    });

    test('removing a stroke drops the picture so it vanishes', () {
      final layer = InkLayer()
        ..add(ink('a', 'p0', [(10, 10, 1), (50, 10, 1)]))
        ..add(ink('b', 'p0', [(10, 20, 1), (50, 20, 1)]));
      final c = Canvas(PictureRecorder());
      layer.paint(c, 'p0');
      layer.remove('a');
      layer.paint(c, 'p0');
      expect(layer.rebuilds, 2);
    });

    test('painting a page with no ink does nothing', () {
      final layer = InkLayer();
      layer.paint(Canvas(PictureRecorder()), 'p0');
      expect(layer.rebuilds, 0);
    });
  });

  group('painting', () {
    Future<ByteData> render(InkLayer layer, ViewState view) async {
      final scene = ValueNotifier(
        const Scene([
          Card(id: 'p0', index: 0, rect: Rect.fromLTWH(20, 20, 60, 60)),
        ]),
      );
      final rec = PictureRecorder();
      InkPainter(
        view: ValueNotifier(view),
        scene: scene,
        ink: layer,
      ).paint(Canvas(rec), const Size(200, 200));
      final img = await rec.endRecording().toImage(200, 200);
      return (await img.toByteData())!;
    }

    int alpha(ByteData d, int x, int y) => d.getUint8((y * 200 + x) * 4 + 3);

    testWidgets('a stroke is drawn in its colour at its place on the page', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(
            ink(
              'a',
              'p0',
              [(5, 30, 1), (55, 30, 1)],
              width: 6,
              color: 0xFFFF0000,
            ),
          );
        final d = await render(layer, const ViewState());
        // Page origin is (20, 20), so the line is at y = 50, x from 25 to 75.
        final o = (50 * 200 + 50) * 4;
        expect(d.getUint8(o), 255, reason: 'red');
        expect(d.getUint8(o + 1), 0);
        expect(alpha(d, 50, 50), 255);
        expect(alpha(d, 50, 60), 0, reason: 'no ink away from the line');
        expect(alpha(d, 50, 52), 255, reason: 'the line is 6 tall');
        expect(alpha(d, 50, 56), 0);
      });
    });

    testWidgets('ink follows the zoom and the pan', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(ink('a', 'p0', [(5, 30, 1), (55, 30, 1)], width: 6));
        // Zoom 2, panned by (-10, -10): the line is at y = 2 * 50 - 10 = 90,
        // 12 px thick.
        final d = await render(layer, const ViewState(x: -10, y: -10, zoom: 2));
        expect(alpha(d, 100, 90), 255);
        expect(alpha(d, 100, 95), 255);
        expect(alpha(d, 100, 98), 0);
      });
    });

    testWidgets('ink may run past the page edge', (tester) async {
      await tester.runAsync(() async {
        // Page is 60 wide (x 20..80); the stroke reaches page x = 110.
        final layer = InkLayer()
          ..add(ink('a', 'p0', [(10, 30, 1), (110, 30, 1)], width: 6));
        final d = await render(layer, const ViewState());
        expect(alpha(d, 100, 50), 255, reason: 'x = 20 + 80, off the page');
      });
    });

    testWidgets('free ink is in canvas space', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(ink('f', null, [(120, 150, 1), (180, 150, 1)], width: 6));
        final d = await render(layer, const ViewState());
        expect(alpha(d, 150, 150), 255);
        expect(alpha(d, 150, 130), 0);
      });
    });

    testWidgets('pressure widens the line', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(
            ink('a', 'p0', [
              for (var i = 0; i <= 10; i++) (5.0 + i * 5, 30, 0.1 + i * 0.09),
            ], width: 8),
          );
        final d = await render(layer, const ViewState());
        int thick(int x) {
          var n = 0;
          for (var y = 30; y < 70; y++) {
            if (alpha(d, x, y) > 128) n++;
          }
          return n;
        }

        expect(thick(70), greaterThan(thick(30)));
      });
    });

    testWidgets('a stroke off screen costs nothing and draws nothing', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(ink('a', 'p0', [(5, 30, 1), (55, 30, 1)], width: 6));
        final d = await render(layer, const ViewState(x: -5000, y: -5000));
        expect(layer.rebuilds, 0, reason: 'culled before any picture is made');
        expect(alpha(d, 50, 50), 0);
      });
    });
  });

  group('LiveInk', () {
    test('collects every sample and grows past its first buffer', () {
      final live = LiveInk()..begin('p0', 3, 0xFF000000);
      for (var i = 0; i < 1000; i++) {
        live.add(i.toDouble(), 0, 0.5, Duration(milliseconds: i));
      }
      expect(live.pointCount, 1000);
      expect(live.samples.length, 3000);
      expect(live.samples[2997], 999);
    });

    test('begin starts clean; end clears and notifies', () {
      final live = LiveInk()..begin(null, 3, 1);
      live.add(1, 1, 1, Duration.zero);
      var n = 0;
      live.addListener(() => n++);
      live.end();
      expect(live.active, isFalse);
      expect(live.pointCount, 0);
      expect(n, 1);
      live.begin('p', 2, 2);
      expect(live.pointCount, 0);
      expect(live.cardId, 'p');
    });

    test('predicts only when asked, along the pen\'s motion', () {
      final live = LiveInk()..begin('p0', 3, 1);
      for (var i = 0; i < 4; i++) {
        live.add(10.0 + i * 2, 5, 1, Duration(milliseconds: i * 2));
      }
      expect(live.predicted, isEmpty);
      live.add(18, 5, 1, const Duration(milliseconds: 8), predict: true);
      expect(live.predicted.length, 4);
      expect(live.predicted[0], greaterThan(18));
    });

    test('measures how old the newest sample is at paint time', () {
      final live = LiveInk()..begin('p0', 3, 1);
      expect(live.stats, 'ink: no stroke yet');
      live.add(1, 1, 1, const Duration(milliseconds: 1000));
      live.recordAge(const Duration(milliseconds: 1006));
      live.recordAge(const Duration(milliseconds: 1010));
      expect(live.ageCount, 2);
      expect(live.ageMaxMs, 10);
      expect(live.stats, 'ink sample age avg 8.0 ms · max 10.0 ms');
      live.recordAge(Duration.zero); // no frame time (tests): ignored
      live.recordAge(const Duration(milliseconds: 900)); // before the sample
      expect(live.ageCount, 2);
    });
  });

  group('InkToolController', () {
    late ValueNotifier<ViewState> view;
    late ValueNotifier<Scene> scene;
    late LiveInk live;
    late FakeInkSink sink;
    late double width;
    late int color;
    late InkToolController tool;

    setUp(() {
      view = ValueNotifier(const ViewState());
      scene = ValueNotifier(
        const Scene([
          Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 600, 800)),
          Card(id: 'p1', index: 1, rect: Rect.fromLTWH(100, 980, 600, 800)),
        ]),
      );
      live = LiveInk();
      sink = FakeInkSink();
      width = 2.5;
      color = 0xFF2B2723;
      tool = InkToolController(
        view: view,
        scene: scene,
        live: live,
        widthDp: () => width,
        color: () => color,
        sink: sink,
      );
    });

    test('a stroke on a page is stored in that page\'s space', () {
      tool.start(pt(150, 200, pressure: 0.3));
      tool.move(pt(200, 210, pressure: 0.5));
      tool.move(pt(250, 200, pressure: 0.4));
      tool.end(pt(300, 205, pressure: 0.2));
      final s = sink.strokes.single;
      expect(s.pageId, 'p0');
      // Screen (150, 200) is world (150, 200): page (50, 100).
      expect([s.samples[0], s.samples[1]], [50, 100]);
      expect(s.samples[2], closeTo(0.3, 1e-6));
      expect(live.active, isFalse);
    });

    test(
      'the pen size is in screen dp: thinner in page points when zoomed in',
      () {
        width = 4;
        view.value = const ViewState(zoom: 2);
        tool.start(pt(300, 300));
        tool.end(pt(400, 300));
        expect(sink.strokes.single.width, closeTo(2, 1e-9));
        sink.strokes.clear();
        view.value = const ViewState(zoom: 0.5);
        tool.start(pt(100, 100));
        tool.end(pt(150, 100));
        expect(sink.strokes.single.width, closeTo(8, 1e-9));
      },
    );

    test('colour and size are read when the stroke starts', () {
      color = 0xFFF4877E;
      width = 6;
      tool.start(pt(150, 200));
      color = 0xFF000000; // changed mid-stroke: no effect
      width = 1;
      tool.end(pt(250, 200));
      expect(sink.strokes.single.color, 0xFFF4877E);
      expect(sink.strokes.single.width, 6);
    });

    test('a device with no pressure draws at full pressure', () {
      tool.start(pt(150, 200));
      tool.end(pt(250, 200));
      final s = sink.strokes.single;
      expect(s.samples[2], 1.0);
    });

    test('a stroke that starts off every page is in canvas space', () {
      tool.start(pt(20, 20));
      tool.end(pt(80, 40));
      final s = sink.strokes.single;
      expect(s.pageId, isNull);
      expect([s.samples[0], s.samples[1]], [20, 20]);
    });

    test(
      'the page where it starts keeps the stroke when it leaves the page',
      () {
        tool.start(pt(650, 200));
        tool.move(pt(900, 200)); // off the right edge
        tool.end(pt(950, 200));
        final s = sink.strokes.single;
        expect(s.pageId, 'p0');
        expect(s.samples[s.samples.length - 3], 850, reason: '950 - 100');
      },
    );

    test('a stroke on the second page uses that page\'s origin', () {
      tool.start(pt(150, 1100));
      tool.end(pt(250, 1100));
      final s = sink.strokes.single;
      expect(s.pageId, 'p1');
      expect([s.samples[0], s.samples[1]], [50, 120]);
    });

    test('follows the pan and zoom of the view', () {
      view.value = const ViewState(x: 50, y: -100, zoom: 2);
      // screen = world * 2 + (50, -100); world (150, 200) is screen (350, 300).
      tool.start(pt(350, 300));
      tool.end(pt(550, 300));
      final s = sink.strokes.single;
      expect([s.samples[0], s.samples[1]], [50, 100]);
      expect(s.samples[s.samples.length - 3], closeTo(150, 1e-4));
    });

    test('every sample is kept live, then the stored stroke is simplified', () {
      tool.start(pt(150, 200));
      for (var i = 1; i <= 200; i++) {
        tool.move(pt(150 + i * 2.0, 200));
      }
      expect(live.pointCount, 201, reason: 'all samples drawn while drawing');
      tool.end(pt(552, 200));
      final s = sink.strokes.single;
      expect(s.samples.length ~/ 3, 2, reason: 'a straight line is two points');
    });

    test('a tap is a dot: one point', () {
      tool.start(pt(300, 300));
      tool.end(pt(300, 300));
      expect(sink.strokes.single.samples.length, 3);
    });

    test('cancel stores nothing and clears the live stroke', () {
      tool.start(pt(150, 200));
      tool.move(pt(200, 200));
      tool.cancel();
      expect(sink.strokes, isEmpty);
      expect(live.active, isFalse);
      tool.end(pt(250, 200)); // a stray end after a cancel is ignored
      expect(sink.strokes, isEmpty);
    });

    test('without a sink the tool does nothing', () {
      tool.sink = null;
      tool.start(pt(150, 200));
      tool.end(pt(250, 200));
      expect(live.active, isFalse);
      expect(tool.isActive, isFalse);
    });

    test('a stationary pen adds no samples; a pressure change does', () {
      tool.start(pt(150, 200, pressure: 0.3));
      tool.move(pt(150, 200, pressure: 0.3));
      tool.move(pt(150, 200, pressure: 0.3));
      expect(live.pointCount, 1);
      tool.move(pt(150, 200, pressure: 0.6));
      expect(live.pointCount, 2);
      tool.cancel();
    });
  });

  test('the pressure curve is applied when drawing, not when storing', () {
    final s = samples([(0, 0, 0.3), (50, 0, 0.3)]);
    final soft = strokePath(s, 8, PressureCurve.soft).getBounds();
    final firm = strokePath(s, 8, PressureCurve.firm).getBounds();
    expect(soft.height, greaterThan(firm.height));
  });
}
