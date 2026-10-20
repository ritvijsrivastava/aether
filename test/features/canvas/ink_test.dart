import 'dart:ui';

import 'package:aether/domain/model/models.dart';
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
  List<(double, double, double)> pts, {
  double width = 4,
  int color = 0xFF000000,
}) =>
    Ink(id: id, docId: 'd', samples: samples(pts), width: width, color: color);

class FakeInkSink implements InkSink {
  final List<({Float32List samples, double width, int color})> strokes = [];
  @override
  String addInk({
    required Float32List samples,
    required double width,
    required int color,
  }) {
    strokes.add((samples: samples, width: width, color: color));
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
    test('keeps strokes, knows how far they reach, tells listeners', () {
      final layer = InkLayer();
      var changes = 0;
      layer.addListener(() => changes++);
      layer.add(ink('a', [(10, 10, 1), (50, 10, 1)], width: 4));
      layer.add(ink('b', [(-100, 90, 1), (30, 200, 1)], width: 4));
      expect(layer.count, 2);
      expect(changes, 2);
      final b = layer.bounds!;
      expect((b.x0, b.y0, b.x1, b.y1), (-102, 8, 52, 202));
      layer.remove('b');
      expect(layer.bounds!.x1, lessThan(100));
      layer.remove('a');
      expect(layer.bounds, isNull);
    });

    test('finds the strokes a circle touches', () {
      final layer = InkLayer()
        ..add(ink('a', [(0, 50, 1), (200, 50, 1)], width: 4))
        ..add(ink('b', [(0, 300, 1), (200, 300, 1)], width: 4));
      expect([for (final i in layer.touching(100, 55, 6)) i.id], ['a']);
      expect(layer.touching(100, 150, 6), isEmpty);
      layer.remove('a');
      expect(layer.touching(100, 55, 6), isEmpty);
      layer.replaceAll([]);
      expect(layer.touching(100, 305, 6), isEmpty);
    });

    test('replaceAll swaps everything at once', () {
      final layer = InkLayer()..add(ink('a', [(1, 1, 1), (2, 2, 1)]));
      layer.replaceAll([
        ink('x', [(1, 1, 1), (9, 9, 1)]),
      ]);
      expect(layer.byId('a'), isNull);
      expect(layer.byId('x'), isNotNull);
    });

    test('a page picture is recorded once, not on every paint', () {
      final layer = InkLayer()..add(ink('a', [(10, 10, 1), (50, 10, 1)]));
      final rec = PictureRecorder();
      final c = Canvas(rec);
      for (var i = 0; i < 20; i++) {
        layer.paint(c);
      }
      expect(layer.rebuilds, 1);
      rec.endRecording().dispose();
    });

    test('a new stroke is drawn on top of the picture, not a rebuild', () {
      final layer = InkLayer()..add(ink('a', [(10, 10, 1), (50, 10, 1)]));
      final c = Canvas(PictureRecorder());
      layer.paint(c);
      for (var i = 0; i < InkLayer.foldAfter; i++) {
        layer.add(ink('n$i', [(10, 30.0 + i, 1), (50, 30.0 + i, 1)]));
        layer.paint(c);
      }
      expect(layer.rebuilds, 1, reason: 'up to the fold limit, no rebuild');
      layer.add(ink('one-more', [(10, 99, 1), (50, 99, 1)]));
      layer.paint(c);
      expect(layer.rebuilds, 2, reason: 'then they are folded in');
    });

    test('removing a stroke drops the picture so it vanishes', () {
      final layer = InkLayer()
        ..add(ink('a', [(10, 10, 1), (50, 10, 1)]))
        ..add(ink('b', [(10, 20, 1), (50, 20, 1)]));
      final c = Canvas(PictureRecorder());
      layer.paint(c);
      layer.remove('a');
      layer.paint(c);
      expect(layer.rebuilds, 2);
    });

    test('painting a page with no ink does nothing', () {
      final layer = InkLayer();
      layer.paint(Canvas(PictureRecorder()));
      expect(layer.rebuilds, 0);
    });
  });

  group('painting', () {
    Future<ByteData> render(InkLayer layer, ViewState view) async {
      final rec = PictureRecorder();
      InkPainter(
        view: ValueNotifier(view),
        ink: layer,
      ).paint(Canvas(rec), const Size(200, 200));
      final img = await rec.endRecording().toImage(200, 200);
      return (await img.toByteData())!;
    }

    int alpha(ByteData d, int x, int y) => d.getUint8((y * 200 + x) * 4 + 3);

    testWidgets('a stroke is drawn in its colour at its place', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(
            ink('a', [(5, 30, 1), (55, 30, 1)], width: 6, color: 0xFFFF0000),
          );
        final d = await render(layer, const ViewState());
        final o = (30 * 200 + 30) * 4;
        expect(d.getUint8(o), 255, reason: 'red');
        expect(d.getUint8(o + 1), 0);
        expect(alpha(d, 30, 30), 255);
        expect(alpha(d, 30, 40), 0, reason: 'no ink away from the line');
        expect(alpha(d, 30, 32), 255, reason: 'the line is 6 tall');
        expect(alpha(d, 30, 36), 0);
      });
    });

    testWidgets('ink follows the zoom and the pan', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(ink('a', [(5, 30, 1), (55, 30, 1)], width: 6));
        // Zoom 2, panned by (-10, -10): the line is at y = 2 * 30 - 10 = 50,
        // 12 px thick.
        final d = await render(layer, const ViewState(x: -10, y: -10, zoom: 2));
        expect(alpha(d, 60, 50), 255);
        expect(alpha(d, 60, 55), 255);
        expect(alpha(d, 60, 58), 0);
      });
    });

    testWidgets('ink far from the origin is drawn where it is', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(ink('f', [(120, 150, 1), (180, 150, 1)], width: 6));
        final d = await render(layer, const ViewState());
        expect(alpha(d, 150, 150), 255);
        expect(alpha(d, 150, 130), 0);
      });
    });

    testWidgets('pressure widens the line', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(
            ink('a', [
              for (var i = 0; i <= 10; i++) (5.0 + i * 5, 30, 0.1 + i * 0.09),
            ], width: 8),
          );
        final d = await render(layer, const ViewState());
        int thick(int x) {
          var n = 0;
          for (var y = 10; y < 50; y++) {
            if (alpha(d, x, y) > 128) n++;
          }
          return n;
        }

        expect(thick(50), greaterThan(thick(10)));
      });
    });

    testWidgets('a stroke off screen costs nothing and draws nothing', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final layer = InkLayer()
          ..add(ink('a', [(5, 30, 1), (55, 30, 1)], width: 6));
        final d = await render(layer, const ViewState(x: -5000, y: -5000));
        expect(layer.rebuilds, 0, reason: 'culled before any picture is made');
        expect(alpha(d, 30, 30), 0);
      });
    });
  });

  group('LiveInk', () {
    test('collects every sample and grows past its first buffer', () {
      final live = LiveInk()..begin(3, 0xFF000000);
      for (var i = 0; i < 1000; i++) {
        live.add(i.toDouble(), 0, 0.5, Duration(milliseconds: i));
      }
      expect(live.pointCount, 1000);
      expect(live.samples.length, 3000);
      expect(live.samples[2997], 999);
    });

    test('begin starts clean; end clears and notifies', () {
      final live = LiveInk()..begin(3, 1);
      live.add(1, 1, 1, Duration.zero);
      var n = 0;
      live.addListener(() => n++);
      live.end();
      expect(live.active, isFalse);
      expect(live.pointCount, 0);
      expect(n, 1);
      live.begin(2, 2);
      expect(live.pointCount, 0);
    });

    test('predicts only when asked, along the pen\'s motion', () {
      final live = LiveInk()..begin(3, 1);
      for (var i = 0; i < 4; i++) {
        live.add(10.0 + i * 2, 5, 1, Duration(milliseconds: i * 2));
      }
      expect(live.predicted, isEmpty);
      live.add(18, 5, 1, const Duration(milliseconds: 8), predict: true);
      expect(live.predicted.length, 4);
      expect(live.predicted[0], greaterThan(18));
    });

    test('measures how old the newest sample is at paint time', () {
      final live = LiveInk()..begin(3, 1);
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
    late LiveInk live;
    late FakeInkSink sink;
    late double width;
    late int color;
    late InkToolController tool;

    setUp(() {
      view = ValueNotifier(const ViewState());
      live = LiveInk();
      sink = FakeInkSink();
      width = 2.5;
      color = 0xFF2B2723;
      tool = InkToolController(
        view: view,
        live: live,
        widthDp: () => width,
        color: () => color,
        sink: sink,
      );
    });

    test('a stroke is stored in world space, whatever the view', () {
      tool.start(pt(150, 200));
      tool.move(pt(250, 220));
      tool.end(pt(350, 200));
      final s = sink.strokes.single;
      expect([s.samples[0], s.samples[1]], [150, 200]);
      expect(s.samples[s.samples.length - 3], 350);
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

    test('follows the pan and zoom of the view', () {
      view.value = const ViewState(x: 50, y: -100, zoom: 2);
      // screen = world * 2 + (50, -100); world (150, 200) is screen (350, 300).
      tool.start(pt(350, 300));
      tool.end(pt(550, 300));
      final s = sink.strokes.single;
      expect([s.samples[0], s.samples[1]], [150, 200]);
      expect(s.samples[s.samples.length - 3], closeTo(250, 1e-4));
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
