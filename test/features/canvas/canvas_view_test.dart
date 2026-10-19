import 'dart:ui';

import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/canvas_view.dart';
import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/engine/page_surface.dart';
import 'package:aether/features/canvas/engine/painters.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:aether/features/canvas/marks/mark_tool.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/gestures.dart'
    show kPrimaryButton, kPrimaryStylusButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(1000, 800);

Future<CanvasController> pumpCanvas(
  WidgetTester tester, {
  CanvasTool tool = CanvasTool.mark,
  bool fingerDraws = false,
  int pages = 6,
  VoidCallback? onCopy,
}) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = CanvasController(
    scene: Scene.column([for (var i = 0; i < pages; i++) const Size(612, 792)]),
    view: const ViewState(x: 200, y: 100),
  )..attach(tester);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(AetherTokens.light),
      home: Scaffold(
        body: CanvasView(
          controller: c,
          surface: SyntheticPageSurface(),
          tool: tool,
          fingerDraws: fingerDraws,
          onCopy: onCopy,
        ),
      ),
    ),
  );
  c.setView(const ViewState(x: 200, y: 100));
  await tester.pump();
  return c;
}

class RecordingMarks implements MarkGestures {
  final List<String> log = [];
  @override
  void markStart(Offset p) => log.add('start ${p.dx.round()},${p.dy.round()}');
  @override
  void markMove(Offset p) => log.add('move ${p.dx.round()},${p.dy.round()}');
  @override
  void markEnd(Offset p) => log.add('end ${p.dx.round()},${p.dy.round()}');
  @override
  void markCancel() => log.add('cancel');
}

class RecordingTools implements ToolGestures {
  final List<(CanvasTool, ToolPoint)> starts = [];
  final List<ToolPoint> points = [];
  @override
  void toolStart(CanvasTool tool, ToolPoint p) {
    starts.add((tool, p));
    points.add(p);
  }

  @override
  void toolMove(ToolPoint p) => points.add(p);
  @override
  void toolEnd(ToolPoint p) => points.add(p);
  @override
  void toolCancel() {}
}

void main() {
  testWidgets('one finger drags the canvas', (tester) async {
    final c = await pumpCanvas(tester);
    final g = await tester.startGesture(
      const Offset(500, 400),
      kind: PointerDeviceKind.touch,
    );
    await g.moveBy(const Offset(-60, 25));
    await g.moveBy(const Offset(-40, 15));
    expect(c.view.value.x, closeTo(100, 1e-6));
    expect(c.view.value.y, closeTo(140, 1e-6));
    await g.up();
  });

  testWidgets('two fingers pinch to zoom', (tester) async {
    final c = await pumpCanvas(tester);
    final a = await tester.startGesture(
      const Offset(400, 400),
      kind: PointerDeviceKind.touch,
      pointer: 1,
    );
    final b = await tester.startGesture(
      const Offset(600, 400),
      kind: PointerDeviceKind.touch,
      pointer: 2,
    );
    await a.moveTo(const Offset(300, 400));
    await b.moveTo(const Offset(700, 400));
    expect(c.view.value.zoom, closeTo(2.0, 1e-6));
    await a.up();
    await b.up();
  });

  testWidgets('a finger never draws, even with a mark tool active', (
    tester,
  ) async {
    final c = await pumpCanvas(tester, tool: CanvasTool.ink);
    final g = await tester.startGesture(
      const Offset(500, 400),
      kind: PointerDeviceKind.touch,
    );
    await g.moveBy(const Offset(-50, 0));
    expect(c.view.value.x, closeTo(150, 1e-6));
    await g.up();
  });

  testWidgets('mouse wheel scrolls; Ctrl+wheel zooms about the pointer', (
    tester,
  ) async {
    final c = await pumpCanvas(tester);
    final mouse = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(500, 400)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(30, 50)));
    expect(c.view.value.x, closeTo(170, 1e-6));
    expect(c.view.value.y, closeTo(50, 1e-6));

    final before = c.view.value.screenToWorld(const Offset(500, 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -50)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.view.value.zoom, greaterThan(1));
    expect(
      (c.view.value.screenToWorld(const Offset(500, 400)) - before).distance,
      lessThan(1e-6),
    );
  });

  testWidgets('Space turns the mouse into a pan tool', (tester) async {
    final c = await pumpCanvas(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final g = await tester.startGesture(
      const Offset(500, 400),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(c.view.value.x, closeTo(240, 1e-6));
    // After Space is released a plain drag does nothing.
    final g2 = await tester.startGesture(
      const Offset(500, 400),
      kind: PointerDeviceKind.mouse,
    );
    await g2.moveBy(const Offset(40, 0));
    await g2.up();
    expect(c.view.value.x, closeTo(240, 1e-6));
  });

  testWidgets('the Pan tool lets a pen move the canvas', (tester) async {
    final c = await pumpCanvas(tester, tool: CanvasTool.pan);
    final g = await tester.startGesture(
      const Offset(500, 400),
      kind: PointerDeviceKind.stylus,
    );
    await g.moveBy(const Offset(0, 30));
    await g.up();
    expect(c.view.value.y, closeTo(130, 1e-6));
  });

  testWidgets('dragging a handle moves its card, with any pointer', (
    tester,
  ) async {
    final c = await pumpCanvas(tester);
    final card = c.scene.value.cards[0];
    final hit = HandleLayout.hitRect(card, c.view.value)!;
    final before = card.rect.topLeft;
    final g = await tester.startGesture(
      hit.center,
      kind: PointerDeviceKind.touch,
    );
    await g.moveBy(const Offset(120, 60));
    await g.up();
    final after = c.scene.value.cards[0].rect.topLeft;
    expect(after - before, const Offset(120, 60));
    expect(c.view.value.x, 200, reason: 'the view itself did not pan');
  });

  testWidgets('keyboard: + and - zoom, Ctrl+0 fits, Ctrl+1 is 100%', (
    tester,
  ) async {
    final c = await pumpCanvas(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.pumpAndSettle();
    expect(c.view.value.zoom, closeTo(1.25, 1e-6));
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.pumpAndSettle();
    expect(c.view.value.zoom, closeTo(1.0, 1e-6));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      c.view.value.zoom,
      lessThan(1),
      reason: 'a 792 pt page fits an 800 px canvas below 100%',
    );
  });

  testWidgets('a touch is ignored while the pen hovers nearby', (tester) async {
    final c = await pumpCanvas(tester, tool: CanvasTool.ink);
    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: const Offset(100, 100));
    await pen.moveTo(const Offset(110, 105)); // hover
    final palm = await tester.startGesture(
      const Offset(500, 400),
      kind: PointerDeviceKind.touch,
      pointer: 5,
    );
    await palm.moveBy(const Offset(-80, 0));
    expect(c.view.value.x, 200, reason: 'palm ignored while the pen is near');
    await palm.up();
  });

  testWidgets('painting 500 pages renders without errors at several zooms', (
    tester,
  ) async {
    final c = await pumpCanvas(tester, pages: 500);
    for (final z in [0.2, 0.5, 1.0, 3.0]) {
      c.setView(ViewState(x: 100, y: -3000 * z, zoom: z));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'zoom $z');
    }
  });

  group('mark tool', () {
    testWidgets('a pen drag with the Mark tool is a mark, not a pan', (
      tester,
    ) async {
      final c = await pumpCanvas(tester);
      final marks = RecordingMarks();
      c.tools = ToolRouter({CanvasTool.mark: MarkHandler(marks)});
      final before = c.view.value;
      final g = await tester.startGesture(
        const Offset(500, 400),
        kind: PointerDeviceKind.stylus,
      );
      await g.moveTo(const Offset(540, 420));
      await g.up();
      expect(marks.log, ['start 500,400', 'move 540,420', 'end 540,420']);
      expect(c.view.value, before);
    });

    testWidgets('a mouse drag with the primary button marks', (tester) async {
      final c = await pumpCanvas(tester);
      final marks = RecordingMarks();
      c.tools = ToolRouter({CanvasTool.mark: MarkHandler(marks)});
      final g = await tester.startGesture(
        const Offset(300, 300),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await g.moveTo(const Offset(350, 310));
      await g.up();
      expect(marks.log.first, 'start 300,300');
      expect(marks.log.last, 'end 350,310');
    });

    for (final tool in [CanvasTool.pan, CanvasTool.ink, CanvasTool.erase]) {
      testWidgets('the ${tool.label} tool does not mark', (tester) async {
        final c = await pumpCanvas(tester, tool: tool);
        final marks = RecordingMarks();
        c.tools = ToolRouter({CanvasTool.mark: MarkHandler(marks)});
        final g = await tester.startGesture(
          const Offset(500, 400),
          kind: PointerDeviceKind.stylus,
        );
        await g.moveTo(const Offset(540, 420));
        await g.up();
        expect(marks.log, isEmpty);
      });
    }

    testWidgets('a finger does not mark by default', (tester) async {
      final c = await pumpCanvas(tester);
      final marks = RecordingMarks();
      c.tools = ToolRouter({CanvasTool.mark: MarkHandler(marks)});
      final g = await tester.startGesture(
        const Offset(500, 400),
        kind: PointerDeviceKind.touch,
      );
      await g.moveBy(const Offset(30, 0));
      await g.up();
      expect(marks.log, isEmpty);
    });

    testWidgets('with "finger draws" on, a finger marks', (tester) async {
      final c = await pumpCanvas(tester, fingerDraws: true);
      final marks = RecordingMarks();
      c.tools = ToolRouter({CanvasTool.mark: MarkHandler(marks)});
      final g = await tester.startGesture(
        const Offset(500, 400),
        kind: PointerDeviceKind.touch,
      );
      await g.moveBy(const Offset(30, 0));
      await g.up();
      expect(marks.log, ['start 500,400', 'move 530,400', 'end 530,400']);
    });

    testWidgets('Escape drops a mark in progress', (tester) async {
      final c = await pumpCanvas(tester);
      final marks = RecordingMarks();
      c.tools = ToolRouter({CanvasTool.mark: MarkHandler(marks)});
      final g = await tester.startGesture(
        const Offset(500, 400),
        kind: PointerDeviceKind.stylus,
      );
      await g.moveTo(const Offset(540, 420));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await g.up();
      expect(marks.log, ['start 500,400', 'move 540,420', 'cancel']);
    });

    testWidgets('Ctrl+C asks to copy the Extract list', (tester) async {
      var copies = 0;
      await pumpCanvas(tester, onCopy: () => copies++);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(copies, 1);
    });

    testWidgets('the mouse shows a text cursor under the Mark tool', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(500, 400)));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.text,
      );
    });
  });

  group('pen events', () {
    Future<RecordingTools> stroke(
      WidgetTester tester,
      PointerDeviceKind kind, {
      required double pressure,
      required double min,
      required double max,
      int buttons = kPrimaryButton,
      CanvasTool tool = CanvasTool.ink,
    }) async {
      final c = await pumpCanvas(tester, tool: tool);
      final rec = RecordingTools();
      c.tools = rec;
      PointerEvent ev(PointerEvent Function() make) => make();
      await tester.sendEventToBinding(
        ev(
          () => PointerDownEvent(
            kind: kind,
            pointer: 5,
            position: const Offset(400, 300),
            buttons: buttons,
            pressure: pressure,
            pressureMin: min,
            pressureMax: max,
          ),
        ),
      );
      await tester.sendEventToBinding(
        PointerMoveEvent(
          kind: kind,
          pointer: 5,
          position: const Offset(420, 300),
          buttons: buttons,
          pressure: pressure,
          pressureMin: min,
          pressureMax: max,
        ),
      );
      await tester.sendEventToBinding(
        PointerUpEvent(
          kind: kind,
          pointer: 5,
          position: const Offset(430, 300),
          pressureMin: min,
          pressureMax: max,
        ),
      );
      return rec;
    }

    testWidgets('a pen reports pressure normalised to 0 to 1', (tester) async {
      final rec = await stroke(
        tester,
        PointerDeviceKind.stylus,
        pressure: 0.4,
        min: 0,
        max: 0.8,
      );
      expect(rec.starts.single.$1, CanvasTool.ink);
      expect(rec.points.first.pressure, closeTo(0.5, 1e-9));
    });

    testWidgets('a pen with a fixed pressure range reports none (X11)', (
      tester,
    ) async {
      final rec = await stroke(
        tester,
        PointerDeviceKind.stylus,
        pressure: 1,
        min: 1,
        max: 1,
      );
      expect(rec.points.first.pressure, isNull);
    });

    testWidgets('a mouse reports none even with a pressure range', (
      tester,
    ) async {
      final rec = await stroke(
        tester,
        PointerDeviceKind.mouse,
        pressure: 1,
        min: 0,
        max: 1,
      );
      expect(rec.points.first.pressure, isNull);
    });

    testWidgets('a pen button held at touch-down switches to Erase', (
      tester,
    ) async {
      final rec = await stroke(
        tester,
        PointerDeviceKind.stylus,
        pressure: 0.4,
        min: 0,
        max: 1,
        buttons: kPrimaryStylusButton,
      );
      expect(rec.starts.single.$1, CanvasTool.erase);
    });
  });
}
