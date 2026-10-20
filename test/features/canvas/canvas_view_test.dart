import 'dart:ui';

import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/canvas_view.dart';
import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/gestures.dart'
    show kPrimaryButton, kPrimaryStylusButton;
import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(1000, 800);

Future<CanvasController> pumpCanvas(
  WidgetTester tester, {
  CanvasTool tool = CanvasTool.ink,
  VoidCallback? onEscape,
  VoidCallback? onDelete,
  ValueChanged<CanvasTool>? onTool,
  VoidCallback? onPointerDownOnCanvas,
}) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = CanvasController(view: const ViewState(x: 200, y: 100))
    ..attach(tester);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(AetherTokens.light),
      home: Scaffold(
        body: CanvasView(
          controller: c,
          tool: tool,
          ink: InkLayer(),
          onEscape: onEscape,
          onDelete: onDelete,
          onTool: onTool,
          onPointerDownOnCanvas: onPointerDownOnCanvas,
        ),
      ),
    ),
  );
  c.setView(const ViewState(x: 200, y: 100));
  await tester.pump();
  return c;
}

class _AsTool implements ToolHandler {
  _AsTool(this.rec);
  final RecordingTools rec;
  @override
  void start(ToolPoint p) => rec.toolStart(CanvasTool.ink, p);
  @override
  void move(ToolPoint p) => rec.toolMove(p);
  @override
  void end(ToolPoint p) => rec.toolEnd(p);
  @override
  void cancel() => rec.toolCancel();
}

class RecordingTools implements ToolGestures {
  final List<String> log = [];
  final List<(CanvasTool, ToolPoint)> starts = [];
  final List<ToolPoint> points = [];
  @override
  void toolStart(CanvasTool tool, ToolPoint p) {
    starts.add((tool, p));
    points.add(p);
    log.add('start');
  }

  @override
  void toolMove(ToolPoint p) => points.add(p);
  @override
  void toolEnd(ToolPoint p) => points.add(p);
  @override
  void toolCancel() => log.add('cancel');
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

  testWidgets('a finger never draws, even with the Ink tool active', (
    tester,
  ) async {
    final c = await pumpCanvas(tester, tool: CanvasTool.ink);
    final rec = RecordingTools();
    c.tools = rec;
    final g = await tester.startGesture(
      const Offset(500, 400),
      kind: PointerDeviceKind.touch,
    );
    await g.moveBy(const Offset(-50, 0));
    expect(c.view.value.x, closeTo(150, 1e-6));
    expect(rec.log, isEmpty, reason: 'the finger panned, it did not draw');
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
    expect(c.view.value.zoom, 1, reason: 'no content: home is 100%');
    expect(c.view.value.worldToScreen(Offset.zero), const Offset(500, 400));
  });

  group('ink tool', () {
    testWidgets('a pen drag with the Ink tool draws, it does not pan', (
      tester,
    ) async {
      final c = await pumpCanvas(tester);
      final rec = RecordingTools();
      c.tools = rec;
      final before = c.view.value;
      final g = await tester.startGesture(
        const Offset(500, 400),
        kind: PointerDeviceKind.stylus,
      );
      await g.moveTo(const Offset(540, 420));
      await g.up();
      expect(rec.log, [
        'start',
      ], reason: 'the end is recorded as a point, not a log line');
      expect(rec.starts.single.$1, CanvasTool.ink);
      expect(rec.points.last.position, const Offset(540, 420));
      expect(c.view.value, before);
    });

    testWidgets('a mouse drag with the primary button draws', (tester) async {
      final c = await pumpCanvas(tester);
      final rec = RecordingTools();
      c.tools = rec;
      final g = await tester.startGesture(
        const Offset(300, 300),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await g.moveTo(const Offset(350, 310));
      await g.up();
      expect(rec.log, ['start']);
      expect(rec.points.last.position, const Offset(350, 310));
    });

    for (final tool in [CanvasTool.pan, CanvasTool.erase]) {
      testWidgets('the ${tool.label} tool does not draw', (tester) async {
        final c = await pumpCanvas(tester, tool: tool);
        final rec = RecordingTools();
        c.tools = ToolRouter({CanvasTool.ink: _AsTool(rec)});
        final g = await tester.startGesture(
          const Offset(500, 400),
          kind: PointerDeviceKind.stylus,
        );
        await g.moveTo(const Offset(540, 420));
        await g.up();
        expect(rec.log, isEmpty);
      });
    }

    testWidgets('a finger does not draw', (tester) async {
      final c = await pumpCanvas(tester, tool: CanvasTool.ink);
      final rec = RecordingTools();
      c.tools = rec;
      final g = await tester.startGesture(
        const Offset(500, 400),
        kind: PointerDeviceKind.touch,
      );
      await g.moveBy(const Offset(30, 0));
      await g.up();
      expect(rec.log, isEmpty);
    });

    testWidgets('Escape drops a stroke in progress', (tester) async {
      final c = await pumpCanvas(tester, tool: CanvasTool.ink);
      final rec = RecordingTools();
      c.tools = rec;
      final g = await tester.startGesture(
        const Offset(500, 400),
        kind: PointerDeviceKind.stylus,
      );
      await g.moveTo(const Offset(540, 420));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await g.up();
      expect(rec.log, ['start', 'cancel']);
    });

    testWidgets('the mouse shows a precise cursor under the Ink tool', (
      tester,
    ) async {
      await pumpCanvas(tester, tool: CanvasTool.ink);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(500, 400)));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.precise,
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
      await tester.sendEventToBinding(
        PointerDownEvent(
          kind: kind,
          pointer: 5,
          position: const Offset(400, 300),
          buttons: buttons,
          pressure: pressure,
          pressureMin: min,
          pressureMax: max,
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

  group('keys for the screen', () {
    testWidgets('Escape and Delete reach the screen', (tester) async {
      var escapes = 0, deletes = 0;
      await pumpCanvas(
        tester,
        onEscape: () => escapes++,
        onDelete: () => deletes++,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect((escapes, deletes), (1, 2));
    });

    testWidgets('any press on the canvas reports itself (to close panels)', (
      tester,
    ) async {
      var downs = 0;
      await pumpCanvas(
        tester,
        tool: CanvasTool.ink,
        onPointerDownOnCanvas: () => downs++,
      );
      final g = await tester.startGesture(const Offset(400, 300));
      await g.up();
      expect(downs, 1);
    });
  });

  group('tool keys', () {
    testWidgets('H P E S choose the tools', (tester) async {
      final chosen = <CanvasTool>[];
      await pumpCanvas(tester, onTool: chosen.add);
      for (final k in [
        LogicalKeyboardKey.keyH,
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.keyS,
      ]) {
        await tester.sendKeyEvent(k);
      }
      expect(chosen, [
        CanvasTool.pan,
        CanvasTool.ink,
        CanvasTool.erase,
        CanvasTool.select,
      ]);
    });

    testWidgets('with Ctrl held they are not tool keys (Ctrl+1 is 100%)', (
      tester,
    ) async {
      final tools = <CanvasTool>[];
      final c = await pumpCanvas(tester, onTool: tools.add);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(seconds: 1));
      expect(tools, isEmpty);
      expect(c.view.value.zoom, 1.0);
    });

    testWidgets('keys that mean nothing are left alone', (tester) async {
      final tools = <CanvasTool>[];
      await pumpCanvas(tester, onTool: tools.add);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
      expect(tools, isEmpty);
    });
  });
}
