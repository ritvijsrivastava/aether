import 'dart:ui';

import 'package:meta/meta.dart';

import '../canvas_ui_state.dart';
import 'pen_config.dart';

/// One sample of a tool's pointer: where, when, and how hard.
@immutable
class ToolPoint {
  const ToolPoint({
    required this.position,
    required this.time,
    required this.kind,
    this.pressure,
  });

  /// Screen space.
  final Offset position;
  final Duration time;
  final PointerDeviceKind kind;

  /// 0 to 1, or null when the device reports none (a mouse, a finger, a pen
  /// under X11): strokes are then drawn at constant width.
  final double? pressure;

  /// Line width factor for this sample under [curve].
  double widthFactor(PressureCurve curve) =>
      pressure == null ? 1.0 : curve.apply(pressure!);
}

/// What the arbiter asks of whichever tool is active. One drag is
/// [toolStart], any number of [toolMove] (every sample, none dropped), then
/// [toolEnd] or, if something interrupts it, [toolCancel].
abstract interface class ToolGestures {
  void toolStart(CanvasTool tool, ToolPoint p);
  void toolMove(ToolPoint p);
  void toolEnd(ToolPoint p);
  void toolCancel();
}

/// One tool's side of a drag.
abstract interface class ToolHandler {
  void start(ToolPoint p);
  void move(ToolPoint p);
  void end(ToolPoint p);
  void cancel();
}

/// Sends each drag to the handler of the tool it started with. A tool with no
/// handler (not built yet, or its document not open) ignores the drag.
class ToolRouter implements ToolGestures {
  ToolRouter(this.handlers);

  final Map<CanvasTool, ToolHandler> handlers;
  ToolHandler? _active;

  @override
  void toolStart(CanvasTool tool, ToolPoint p) {
    _active?.cancel();
    _active = handlers[tool];
    _active?.start(p);
  }

  @override
  void toolMove(ToolPoint p) => _active?.move(p);

  @override
  void toolEnd(ToolPoint p) {
    final h = _active;
    _active = null;
    h?.end(p);
  }

  @override
  void toolCancel() {
    final h = _active;
    _active = null;
    h?.cancel();
  }
}
