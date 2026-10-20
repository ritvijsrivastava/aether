import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/ink/ink_geometry.dart';
import '../engine/view_state.dart';
import '../input/tool_gestures.dart';
import 'ink_layer.dart';

/// Where a finished stroke goes. Returns the new stroke's id at once; the
/// write is queued behind it.
abstract interface class InkSink {
  String addInk({
    required Float32List samples,
    required double width,
    required int color,
  });
}

/// The Ink tool: a pen drag becomes a pressure-width stroke.
///
/// The stroke is stored in world space. The line width is
/// the chosen size in screen dp at the moment of drawing, so what is drawn
/// matches the size picked whatever the zoom.
class InkToolController implements ToolHandler {
  InkToolController({
    required this.view,
    required this.live,
    required this.widthDp,
    required this.color,
    this.sink,
    this.predict = false,
  });

  final ValueListenable<ViewState> view;
  final LiveInk live;

  /// The chosen pen size, in dp, and colour (ARGB), read at pointer-down.
  final double Function() widthDp;
  final int Function() color;

  InkSink? sink;

  /// Extend the live stroke by a predicted point or two (Android).
  final bool predict;

  /// A stroke is simplified to this many screen pixels (SPEC 5.5: ~0.15 px).
  static const double simplifyPx = 0.15;

  /// The smallest line a zoomed-in stroke may be given, in page points.
  static const double minWidth = 0.05;

  double _width = 2.5;
  bool _active = false;
  Offset _lastScreen = Offset.zero;
  double _lastPressure = -1;

  bool get isActive => _active;

  Offset _local(Offset screen) => view.value.screenToWorld(screen);

  @override
  void start(ToolPoint p) {
    if (sink == null) return;
    _width = (widthDp() / view.value.zoom).clamp(minWidth, double.infinity);
    _active = true;
    live.begin(_width, color());
    _add(p);
  }

  void _add(ToolPoint p) {
    final l = _local(p.position);
    final pressure = p.pressure ?? 1.0;
    // A pen that has not moved adds nothing, unless it pressed differently.
    if (p.position == _lastScreen &&
        pressure == _lastPressure &&
        live.pointCount > 0) {
      return;
    }
    _lastScreen = p.position;
    _lastPressure = pressure;
    live.add(l.dx, l.dy, pressure, p.time, predict: predict);
  }

  @override
  void move(ToolPoint p) {
    if (_active) _add(p);
  }

  @override
  void end(ToolPoint p) {
    if (!_active) return;
    _add(p);
    final raw = Float32List.fromList(live.samples);
    final tol = simplifyPx / view.value.zoom;
    final out = InkGeometry.simplify(raw, tol);
    _finish();
    if (out.isEmpty) return;
    sink?.addInk(samples: out, width: _width, color: live.color);
  }

  @override
  void cancel() {
    if (_active) _finish();
  }

  void _finish() {
    _active = false;
    _lastPressure = -1;
    _lastScreen = Offset.zero;
    live.end();
  }
}
