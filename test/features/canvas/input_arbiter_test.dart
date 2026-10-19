import 'dart:ui';

import 'package:aether/features/canvas/input/input_arbiter.dart';
import 'package:flutter_test/flutter_test.dart';

class Rec implements GestureSink {
  final List<String> log = [];
  Offset pan = Offset.zero;
  double zoom = 1;
  Offset? fling;
  final List<Offset> cardDrags = [];

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
  void panEnd(Offset velocity) {
    fling = velocity;
    log.add('panEnd');
  }

  @override
  void cardDragStart(String id) => log.add('cardStart:$id');
  @override
  void cardDragBy(Offset d) {
    cardDrags.add(d);
    log.add('cardBy');
  }

  @override
  void cardDragEnd() => log.add('cardEnd');

  final List<Offset> marks = [];
  @override
  void markStart(Offset p) {
    marks.add(p);
    log.add('markStart');
  }

  @override
  void markMove(Offset p) {
    marks.add(p);
    log.add('markMove');
  }

  @override
  void markEnd(Offset p) {
    marks.add(p);
    log.add('markEnd');
  }

  @override
  void markCancel() => log.add('markCancel');

  int count(String s) => log.where((e) => e == s).length;
}

class Ctx implements ArbiterContext {
  @override
  bool panTool = false;
  @override
  bool markTool = false;
  @override
  bool spaceHeld = false;
  @override
  bool fingerDraws = false;
  Rect? handle;
  @override
  String? handleAt(Offset s) =>
      handle != null && handle!.contains(s) ? 'card1' : null;
}

PointerSample s(
  int id,
  PointerDeviceKind k,
  double x,
  double y,
  int ms, {
  int buttons = 0,
  double radius = 0,
}) => PointerSample(
  id: id,
  kind: k,
  position: Offset(x, y),
  time: Duration(milliseconds: ms),
  buttons: buttons,
  radiusMajor: radius,
);

const touch = PointerDeviceKind.touch;
const mouse = PointerDeviceKind.mouse;
const pen = PointerDeviceKind.stylus;

void main() {
  late Rec rec;
  late Ctx ctx;
  late InputArbiter a;
  setUp(() {
    rec = Rec();
    ctx = Ctx();
    a = InputArbiter(rec, ctx);
  });

  group('finger', () {
    test('one finger pans and flings on release', () {
      a.down(s(1, touch, 100, 100, 0));
      for (var i = 1; i <= 10; i++) {
        a.move(s(1, touch, 100 + i * 10, 100, i * 8));
      }
      a.up(s(1, touch, 200, 100, 88));
      expect(rec.pan, const Offset(100, 0));
      expect(rec.fling!.dx, greaterThan(1000)); // 10 px per 8 ms = 1250 px/s
      expect(rec.fling!.dy, 0);
    });

    test('a slow release has no fling', () {
      a.down(s(1, touch, 100, 100, 0));
      a.move(s(1, touch, 110, 100, 10));
      a.move(s(1, touch, 110, 100, 400));
      a.up(s(1, touch, 110, 100, 800));
      expect(rec.fling!.distance, lessThan(50));
    });

    test('two fingers pinch about their centre and pan with it', () {
      a.down(s(1, touch, 100, 300, 0));
      a.down(s(2, touch, 200, 300, 5));
      a.move(s(1, touch, 50, 300, 20)); // spread: distance 100 -> 150
      a.move(s(2, touch, 200, 300, 21));
      expect(rec.zoom, closeTo(1.5, 1e-9));
      // Centroid moved from (150,300) to (125,300): pan -25.
      expect(rec.pan.dx, closeTo(-25, 1e-9));
    });

    test('lifting one of two fingers continues as a pan with no fling', () {
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

    test('a finger never marks: with a tool active it still pans', () {
      ctx.panTool = false;
      a.down(s(1, touch, 0, 0, 0));
      a.move(s(1, touch, 10, 0, 10));
      expect(rec.pan.dx, 10);
    });

    test(
      'finger-draws on: one finger is left to the tool, two still pinch',
      () {
        ctx.fingerDraws = true;
        a.down(s(1, touch, 100, 100, 0));
        a.move(s(1, touch, 150, 100, 10));
        expect(rec.pan, Offset.zero);
        a.down(s(2, touch, 200, 100, 20));
        a.move(s(2, touch, 300, 100, 30));
        expect(rec.zoom, greaterThan(1));
      },
    );
  });

  group('mouse and pen', () {
    test('a plain left drag does nothing in M2 (no tool consumes it)', () {
      a.down(s(1, mouse, 10, 10, 0, buttons: 1));
      a.move(s(1, mouse, 60, 10, 10, buttons: 1));
      expect(rec.pan, Offset.zero);
    });

    test('left drag pans under the Pan tool', () {
      ctx.panTool = true;
      a.down(s(1, mouse, 10, 10, 0, buttons: 1));
      a.move(s(1, mouse, 60, 40, 10, buttons: 1));
      a.up(s(1, mouse, 60, 40, 20));
      expect(rec.pan, const Offset(50, 30));
      expect(rec.fling, Offset.zero);
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
    });

    test('a pen pans only under the Pan tool', () {
      a.down(s(1, pen, 0, 0, 0, buttons: 1));
      a.move(s(1, pen, 30, 0, 10, buttons: 1));
      a.up(s(1, pen, 30, 0, 20));
      expect(rec.pan, Offset.zero);
      ctx.panTool = true;
      a.down(s(2, pen, 0, 0, 100, buttons: 1));
      a.move(s(2, pen, 30, 0, 110, buttons: 1));
      a.up(s(2, pen, 30, 0, 120));
      expect(rec.pan, const Offset(30, 0));
    });

    test('scroll pans; ctrl+scroll zooms about the pointer', () {
      a.scroll(const Offset(400, 300), const Offset(0, 40), ctrl: false);
      expect(rec.pan, const Offset(0, -40));
      a.scroll(const Offset(400, 300), const Offset(0, -100), ctrl: true);
      expect(rec.zoom, closeTo(1.0 * 2.718281828, 1e-6));
    });

    test('trackpad pan-zoom reports increments, not totals', () {
      a.panZoomStart();
      a.panZoomUpdate(const Offset(100, 100), const Offset(10, 0), 1.1);
      a.panZoomUpdate(const Offset(100, 100), const Offset(25, 5), 1.21);
      expect(rec.pan, const Offset(25, 5));
      expect(rec.zoom, closeTo(1.21, 1e-9));
    });
  });

  group('card handles', () {
    setUp(() => ctx.handle = const Rect.fromLTWH(50, 50, 120, 36));

    test('any pointer on a handle drags its card', () {
      for (final k in [touch, mouse, pen]) {
        rec.log.clear();
        rec.cardDrags.clear();
        a.down(s(1, k, 60, 60, 0, buttons: 1));
        a.move(s(1, k, 90, 70, 10, buttons: 1));
        a.up(s(1, k, 90, 70, 20));
        expect(rec.log.first, 'start');
        expect(rec.log, contains('cardStart:card1'));
        expect(rec.cardDrags.single, const Offset(30, 10));
        expect(rec.log.last, 'cardEnd');
        expect(rec.pan, Offset.zero);
      }
    });

    test('a second finger during a card drag is ignored', () {
      a.down(s(1, touch, 60, 60, 0));
      a.down(s(2, touch, 400, 400, 5));
      a.move(s(2, touch, 500, 400, 10));
      a.move(s(1, touch, 80, 60, 15));
      expect(rec.zoom, 1);
      expect(rec.cardDrags.single, const Offset(20, 0));
    });
  });

  group('palm and pen safety net', () {
    test('touches are ignored while the pen hovers and for 250 ms after', () {
      a.hover(s(9, pen, 300, 300, 1000));
      a.down(s(1, touch, 10, 10, 1100));
      a.move(s(1, touch, 60, 10, 1110));
      expect(rec.pan, Offset.zero, reason: 'pen still near');
      a.up(s(1, touch, 60, 10, 1120));
      // 300 ms after the last pen sample: touches work again.
      a.down(s(2, touch, 10, 10, 1300));
      a.move(s(2, touch, 60, 10, 1310));
      expect(rec.pan.dx, 50);
    });

    test('a pen landing mid-pan cancels the finger gesture', () {
      a.down(s(1, touch, 10, 10, 0));
      a.move(s(1, touch, 40, 10, 10));
      a.down(s(9, pen, 200, 200, 20, buttons: 1));
      final panned = rec.pan;
      a.move(s(1, touch, 90, 10, 30));
      expect(rec.pan, panned, reason: 'the interrupted finger no longer pans');
      expect(rec.fling, Offset.zero);
    });

    test('a palm-sized contact is ignored', () {
      a.down(s(1, touch, 10, 10, 0, radius: 40));
      a.move(s(1, touch, 90, 10, 10, radius: 40));
      expect(rec.pan, Offset.zero);
    });

    test('cancel ends a pan cleanly', () {
      a.down(s(1, touch, 10, 10, 0));
      a.move(s(1, touch, 40, 10, 10));
      a.cancel(s(1, touch, 40, 10, 20));
      expect(rec.count('panEnd'), 1);
      // The arbiter is idle again and accepts a new gesture.
      a.down(s(2, touch, 0, 0, 500));
      a.move(s(2, touch, 7, 0, 510));
      expect(rec.pan.dx, 37);
    });
  });

  group('mark tool', () {
    setUp(() => ctx.markTool = true);

    test('a pen drag is a mark, not a pan', () {
      a.down(s(9, pen, 100, 100, 0, buttons: 1));
      a.move(s(9, pen, 140, 110, 10, buttons: 1));
      a.up(s(9, pen, 180, 120, 20));
      expect(rec.log.where((e) => e.startsWith('mark')).toList(), [
        'markStart',
        'markMove',
        'markEnd',
      ]);
      expect(rec.marks, [
        const Offset(100, 100),
        const Offset(140, 110),
        const Offset(180, 120),
      ]);
      expect(rec.pan, Offset.zero);
    });

    test('a mouse drag with the primary button marks', () {
      a.down(s(1, mouse, 10, 10, 0, buttons: 1));
      a.move(s(1, mouse, 30, 10, 5, buttons: 1));
      a.up(s(1, mouse, 30, 10, 9));
      expect(rec.count('markStart'), 1);
      expect(rec.count('markEnd'), 1);
    });

    test('a mouse press with no button held does nothing', () {
      a.down(s(1, mouse, 10, 10, 0));
      expect(rec.count('markStart'), 0);
    });

    test('the eraser end of a pen does not mark', () {
      a.down(s(9, PointerDeviceKind.invertedStylus, 10, 10, 0, buttons: 1));
      expect(rec.count('markStart'), 0);
    });

    test('Space, the Pan tool or the middle button pan instead', () {
      ctx.spaceHeld = true;
      a.down(s(1, mouse, 10, 10, 0, buttons: 1));
      a.move(s(1, mouse, 30, 10, 5, buttons: 1));
      a.up(s(1, mouse, 30, 10, 9));
      expect(rec.count('markStart'), 0);
      expect(rec.pan, const Offset(20, 0));
    });

    test('a finger still pans while "finger draws" is off', () {
      a.down(s(1, touch, 10, 10, 0));
      a.move(s(1, touch, 40, 10, 10));
      a.up(s(1, touch, 40, 10, 20));
      expect(rec.count('markStart'), 0);
      expect(rec.pan, const Offset(30, 0));
    });

    test('with "finger draws" on, one finger marks', () {
      ctx.fingerDraws = true;
      a.down(s(1, touch, 10, 10, 0));
      a.move(s(1, touch, 40, 10, 10));
      a.up(s(1, touch, 40, 10, 20));
      expect(rec.count('markStart'), 1);
      expect(rec.count('markEnd'), 1);
      expect(rec.pan, Offset.zero);
    });

    test('a second finger cancels the mark and pinches', () {
      ctx.fingerDraws = true;
      a.down(s(1, touch, 100, 300, 0));
      a.move(s(1, touch, 105, 300, 5));
      a.down(s(2, touch, 200, 300, 10));
      expect(rec.count('markCancel'), 1);
      a.move(s(2, touch, 250, 300, 20));
      expect(rec.zoom, greaterThan(1));
      a.up(s(1, touch, 105, 300, 30));
      a.up(s(2, touch, 250, 300, 31));
      expect(rec.count('markEnd'), 0, reason: 'a cancelled mark never ends');
    });

    test('a pen landing cancels a finger mark', () {
      ctx.fingerDraws = true;
      a.down(s(1, touch, 10, 10, 0));
      a.move(s(1, touch, 40, 10, 10));
      a.down(s(9, pen, 200, 200, 20, buttons: 1));
      expect(rec.count('markCancel'), 1);
      a.move(s(1, touch, 90, 10, 30));
      expect(rec.count('markMove'), 1, reason: 'the finger no longer marks');
    });

    test('Escape drops the mark in progress', () {
      a.down(s(9, pen, 100, 100, 0, buttons: 1));
      a.move(s(9, pen, 140, 110, 10, buttons: 1));
      a.escape();
      expect(rec.count('markCancel'), 1);
      a.up(s(9, pen, 180, 120, 20));
      expect(rec.count('markEnd'), 0);
      // And the arbiter is ready for the next one.
      a.down(s(9, pen, 100, 100, 100, buttons: 1));
      expect(rec.count('markStart'), 2);
    });

    test('a pointer cancel drops the mark', () {
      a.down(s(9, pen, 100, 100, 0, buttons: 1));
      a.cancel(s(9, pen, 100, 100, 10));
      expect(rec.count('markCancel'), 1);
      expect(rec.count('markEnd'), 0);
    });

    test('a card handle still drags its card under the Mark tool', () {
      ctx.handle = const Rect.fromLTWH(0, 0, 100, 50);
      a.down(s(9, pen, 10, 10, 0, buttons: 1));
      expect(rec.count('markStart'), 0);
      expect(rec.log, contains('cardStart:card1'));
    });
  });
}
