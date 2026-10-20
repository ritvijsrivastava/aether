import 'dart:ui';

import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/input/input_arbiter.dart';
import 'package:aether/features/canvas/input/pen_config.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:flutter_test/flutter_test.dart';

class Rec implements GestureSink {
  final List<String> log = [];
  Offset pan = Offset.zero;
  double zoom = 1;
  Offset fling = Offset.zero;
  final List<CanvasTool> tools = [];
  final List<ToolPoint> points = [];

  @override
  void gestureStart() => log.add('start');
  @override
  void panBy(Offset d) {
    pan += d;
    log.add('pan');
  }

  @override
  void zoomPan({
    required Offset anchor,
    required double factor,
    required Offset pan,
  }) {
    zoom *= factor;
    this.pan += pan;
    log.add('zoomPan');
  }

  @override
  void panEnd(Offset v) {
    fling = v;
    log.add('panEnd');
  }

  @override
  void toolStart(CanvasTool t, ToolPoint p) {
    tools.add(t);
    points.add(p);
    log.add('toolStart');
  }

  @override
  void toolMove(ToolPoint p) {
    points.add(p);
    log.add('toolMove');
  }

  @override
  void toolEnd(ToolPoint p) {
    points.add(p);
    log.add('toolEnd');
  }

  @override
  void toolCancel() => log.add('toolCancel');

  int count(String s) => log.where((e) => e == s).length;
}

class Ctx implements ArbiterContext {
  @override
  CanvasTool tool = CanvasTool.ink;
  @override
  PenConfig pen = const PenConfig();
  @override
  bool spaceHeld = false;
}

const touch = PointerDeviceKind.touch;
const mouse = PointerDeviceKind.mouse;
const pen = PointerDeviceKind.stylus;
const eraser = PointerDeviceKind.invertedStylus;

PointerSample s(
  int id,
  PointerDeviceKind k,
  double x,
  double y,
  int ms, {
  int buttons = 0,
  double? pressure,
}) => PointerSample(
  id: id,
  kind: k,
  position: Offset(x, y),
  time: Duration(milliseconds: ms),
  buttons: buttons,
  pressure: pressure,
);

void main() {
  late Rec rec;
  late Ctx ctx;
  late InputArbiter a;

  setUp(() {
    rec = Rec();
    ctx = Ctx();
    a = InputArbiter(rec, ctx);
  });

  group('one finger', () {
    test('pans at once, 1:1, and never draws', () {
      a.down(s(1, touch, 100, 100, 0));
      a.move(s(1, touch, 130, 90, 10));
      a.move(s(1, touch, 150, 80, 20));
      expect(rec.pan, const Offset(50, -20));
      expect(rec.tools, isEmpty);
    });

    test('a fast release flings, a slow one does not', () {
      a.down(s(1, touch, 0, 0, 0));
      for (var i = 1; i <= 5; i++) {
        a.move(s(1, touch, i * 20.0, 0, i * 16));
      }
      a.up(s(1, touch, 100, 0, 96));
      expect(rec.fling.dx, greaterThan(500));

      rec = Rec();
      a = InputArbiter(rec, ctx);
      a.down(s(1, touch, 0, 0, 0));
      a.move(s(1, touch, 5, 0, 300));
      a.up(s(1, touch, 5, 0, 600));
      expect(rec.fling, Offset.zero);
    });

    test('pans with any tool selected', () {
      for (final t in CanvasTool.values) {
        ctx.tool = t;
        rec = Rec();
        a = InputArbiter(rec, ctx);
        a.down(s(1, touch, 0, 0, 0));
        a.move(s(1, touch, 10, 0, 10));
        a.up(s(1, touch, 10, 0, 20));
        expect(rec.pan.dx, 10, reason: t.label);
        expect(rec.tools, isEmpty, reason: t.label);
      }
    });
  });

  group('two fingers', () {
    test('spreading zooms about the midpoint', () {
      a.down(s(1, touch, 400, 400, 0));
      a.down(s(2, touch, 600, 400, 5));
      a.move(s(1, touch, 300, 400, 10));
      a.move(s(2, touch, 700, 400, 15));
      expect(rec.zoom, closeTo(2, 1e-9));
    });

    test('moving both together pans', () {
      a.down(s(1, touch, 100, 300, 0));
      a.down(s(2, touch, 200, 300, 5));
      a.move(s(1, touch, 90, 300, 10));
      a.move(s(2, touch, 190, 300, 15));
      expect(rec.zoom, closeTo(1, 1e-9));
      expect(rec.pan.dx, closeTo(-10, 1e-9));
    });

    test('lifting one carries on as a pan with the other, no fling', () {
      a.down(s(1, touch, 100, 300, 0));
      a.down(s(2, touch, 200, 300, 5));
      a.move(s(1, touch, 90, 300, 20));
      a.up(s(1, touch, 90, 300, 30));
      final before = rec.pan;
      a.move(s(2, touch, 230, 320, 40));
      expect(rec.pan - before, const Offset(30, 20));
      a.up(s(2, touch, 230, 320, 50));
      expect(rec.fling, Offset.zero);
    });

    test('a third finger is ignored', () {
      a.down(s(1, touch, 100, 300, 0));
      a.down(s(2, touch, 200, 300, 5));
      a.down(s(3, touch, 300, 300, 6));
      a.move(s(3, touch, 400, 300, 10));
      expect(rec.zoom, 1);
      expect(rec.pan, Offset.zero);
      a.up(s(3, touch, 400, 300, 20));
      a.move(s(2, touch, 260, 300, 30));
      expect(rec.zoom, greaterThan(1), reason: 'the pair still works');
    });
  });

  group('stylus', () {
    test('applies the active tool and reports pressure', () {
      a.down(s(9, pen, 100, 100, 0, buttons: 1, pressure: 0.3));
      a.move(s(9, pen, 110, 100, 5, buttons: 1, pressure: 0.5));
      a.up(s(9, pen, 120, 100, 10, pressure: 0.2));
      expect(rec.tools, [CanvasTool.ink]);
      expect(rec.points.map((p) => p.pressure), [0.3, 0.5, 0.2]);
      expect(rec.log, ['start', 'toolStart', 'toolMove', 'toolEnd']);
      expect(rec.pan, Offset.zero);
    });

    test('the Pan tool makes it pan', () {
      ctx.tool = CanvasTool.pan;
      a.down(s(9, pen, 0, 0, 0, buttons: 1));
      a.move(s(9, pen, 30, 0, 10, buttons: 1));
      a.up(s(9, pen, 30, 0, 20));
      expect(rec.pan, const Offset(30, 0));
      expect(rec.fling, Offset.zero, reason: 'a pen never flings');
    });

    test('the eraser end erases whatever the tool is', () {
      a.down(s(9, eraser, 10, 10, 0, buttons: 1));
      expect(rec.tools, [CanvasTool.erase]);
    });

    test('the S Pen button at touch-down erases for that stroke', () {
      a = InputArbiter(
        rec,
        ctx..pen = const PenConfig(buttons: PenButtonMap.sPen),
      );
      a.down(s(9, pen, 10, 10, 0, buttons: 3));
      expect(rec.tools, [CanvasTool.erase]);
    });

    test('Escape drops the stroke and the next one starts clean', () {
      a.down(s(9, pen, 100, 100, 0, buttons: 1));
      a.move(s(9, pen, 140, 110, 10, buttons: 1));
      a.escape();
      expect(rec.count('toolCancel'), 1);
      a.up(s(9, pen, 180, 120, 20));
      expect(rec.count('toolEnd'), 0);
      a.down(s(9, pen, 100, 100, 100, buttons: 1));
      expect(rec.count('toolStart'), 2);
    });

    test('a pointer cancel drops the stroke', () {
      a.down(s(9, pen, 100, 100, 0, buttons: 1));
      a.cancel(s(9, pen, 100, 100, 10));
      expect(rec.count('toolCancel'), 1);
      expect(rec.count('toolEnd'), 0);
    });

    test(
      'fingers are ignored while it draws, and it stops a pan under way',
      () {
        a.down(s(9, pen, 100, 100, 0, buttons: 1));
        a.down(s(1, touch, 300, 300, 5));
        a.move(s(1, touch, 400, 300, 10));
        expect(rec.pan, Offset.zero);
        a.up(s(9, pen, 110, 100, 20));
        a.up(s(1, touch, 400, 300, 30));

        rec = Rec();
        a = InputArbiter(rec, ctx);
        a.down(s(1, touch, 0, 0, 0));
        a.move(s(1, touch, 20, 0, 10));
        a.down(s(9, pen, 100, 100, 20, buttons: 1));
        a.move(s(1, touch, 60, 0, 30));
        expect(rec.pan.dx, 20, reason: 'the finger no longer pans');
        expect(rec.tools, [CanvasTool.ink]);
      },
    );
  });

  group('mouse and trackpad', () {
    test('a primary drag applies the tool', () {
      a.down(s(1, mouse, 10, 10, 0, buttons: 1));
      a.move(s(1, mouse, 60, 10, 10, buttons: 1));
      expect(rec.pan, Offset.zero);
      expect(rec.tools, [CanvasTool.ink]);
    });

    test('a primary drag pans under the Pan tool', () {
      ctx.tool = CanvasTool.pan;
      a.down(s(1, mouse, 10, 10, 0, buttons: 1));
      a.move(s(1, mouse, 60, 40, 10, buttons: 1));
      a.up(s(1, mouse, 60, 40, 20));
      expect(rec.pan, const Offset(50, 30));
    });

    test('Space-drag and middle-drag pan', () {
      ctx.spaceHeld = true;
      a.down(s(1, mouse, 0, 0, 0, buttons: 1));
      a.move(s(1, mouse, 20, 0, 10, buttons: 1));
      a.up(s(1, mouse, 20, 0, 20));
      ctx.spaceHeld = false;
      a.down(s(2, mouse, 0, 0, 30, buttons: 4));
      a.move(s(2, mouse, 0, 15, 40, buttons: 4));
      a.up(s(2, mouse, 0, 15, 50));
      expect(rec.pan, const Offset(20, 15));
      expect(rec.tools, isEmpty);
    });

    test('scroll pans; ctrl+scroll zooms about the pointer', () {
      a.scroll(const Offset(400, 300), const Offset(0, 40), ctrl: false);
      expect(rec.pan, const Offset(0, -40));
      a.scroll(const Offset(400, 300), const Offset(0, -100), ctrl: true);
      expect(rec.zoom, closeTo(2.718281828, 1e-6));
    });

    test('trackpad pan-zoom reports increments, not totals', () {
      a.panZoomStart();
      a.panZoomUpdate(const Offset(100, 100), const Offset(10, 0), 1.1);
      a.panZoomUpdate(const Offset(100, 100), const Offset(30, 0), 1.21);
      expect(rec.pan, const Offset(30, 0));
      expect(rec.zoom, closeTo(1.21, 1e-9));
    });
  });
}
