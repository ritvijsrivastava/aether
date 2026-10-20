import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/physics.dart' show FrictionSimulation;
import 'package:flutter/scheduler.dart';

import '../input/input_arbiter.dart';
import '../input/tool_gestures.dart';
import '../canvas_ui_state.dart' show CanvasTool;
import 'view_state.dart';

/// Owns the canvas view and implements the gestures the arbiter asks for.
/// Painters listen to [view] directly, so a pan or zoom repaints layers
/// without rebuilding any widget. The view is never clamped: the canvas is
/// infinite.
class CanvasController implements GestureSink {
  CanvasController({ViewState view = const ViewState()})
    : view = ValueNotifier<ViewState>(view);

  final ValueNotifier<ViewState> view;

  /// Where the content reaches in world space (null when the board is empty);
  /// "fit" frames it.
  Rect? Function()? contentBounds;

  /// Size of the canvas surface in logical px; set by the view on layout.
  Size viewport = Size.zero;

  /// Screen area covered by floating controls; "fit" centres in what is left.
  EdgeInsets insets = EdgeInsets.zero;

  /// Receives the active tool's drags. Set once a document is open; until then
  /// tool drags are ignored.
  ToolGestures? tools;

  Ticker? _ticker;
  _Motion? _motion;

  /// Must be called once with the widget's [TickerProvider].
  void attach(TickerProvider vsync) {
    _ticker ??= vsync.createTicker(_tick);
  }

  void dispose() {
    _ticker?.dispose();
    view.dispose();
  }

  bool get isAnimating => _motion != null;

  // --- view mutation -------------------------------------------------------

  void _set(ViewState v) {
    view.value = v;
  }

  void setView(ViewState v) {
    _stop();
    _set(v);
  }

  @override
  void gestureStart() {
    _stop();
  }

  @override
  void panBy(Offset delta) => _set(view.value.panBy(delta));

  @override
  void zoomPan({
    required Offset anchor,
    required double factor,
    required Offset pan,
  }) {
    _set(view.value.zoomAt(anchor, factor).panBy(pan));
  }

  @override
  void panEnd(Offset velocity) {
    if (velocity.distance < 80) return;
    _motion = _Fling(view.value, velocity);
    _ticker?.start();
  }

  // --- tools ---------------------------------------------------------------------

  @override
  void toolStart(CanvasTool tool, ToolPoint p) => tools?.toolStart(tool, p);

  @override
  void toolMove(ToolPoint p) => tools?.toolMove(p);

  @override
  void toolEnd(ToolPoint p) => tools?.toolEnd(p);

  @override
  void toolCancel() => tools?.toolCancel();

  // --- zoom and fit ---------------------------------------------------------

  /// The centre of the area not covered by floating controls.
  Offset get _focus => Offset(
    insets.left + (viewport.width - insets.horizontal) / 2,
    insets.top + (viewport.height - insets.vertical) / 2,
  );

  void zoomBy(double factor, {bool animate = true}) {
    final target = view.value.zoomAt(_focus, factor);
    animate ? animateTo(target) : setView(target);
  }

  void zoomTo(double zoom) {
    animateTo(
      view.value.withZoomAt(
        _focus,
        zoom.clamp(ViewState.minZoom, ViewState.maxZoom),
      ),
    );
  }

  /// Frames the content, or goes home (origin in the middle at 100%) when
  /// the board is empty.
  void fit({bool animate = true}) {
    if (viewport.isEmpty) return;
    final b = contentBounds?.call();
    final target = b == null || b.isEmpty
        ? ViewState(x: _focus.dx, y: _focus.dy)
        : ViewState.fitRect(b, viewport, insets: insets);
    animate ? animateTo(target) : setView(target);
  }

  void animateTo(
    ViewState target, {
    Duration duration = const Duration(milliseconds: 240),
  }) {
    if (target == view.value) return;
    _motion = _Tween(view.value, target, duration);
    _ticker?.start();
  }

  // --- animation ---------------------------------------------------------------

  void _stop() {
    _motion = null;
    if (_ticker?.isActive ?? false) _ticker!.stop();
  }

  void _tick(Duration elapsed) {
    final m = _motion;
    if (m == null) {
      _ticker?.stop();
      return;
    }
    view.value = m.at(elapsed);
    if (m.isDone(elapsed)) _stop();
  }
}

abstract class _Motion {
  ViewState at(Duration t);
  bool isDone(Duration t);
}

class _Tween implements _Motion {
  _Tween(this.from, this.to, this.duration);
  final ViewState from, to;
  final Duration duration;

  @override
  ViewState at(Duration t) {
    final p = (t.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
    return ViewState.lerp(from, to, Curves.easeOutCubic.transform(p));
  }

  @override
  bool isDone(Duration t) => t >= duration;
}

class _Fling implements _Motion {
  _Fling(this.from, Offset v)
    : _x = FrictionSimulation(0.135, from.x, v.dx),
      _y = FrictionSimulation(0.135, from.y, v.dy);

  final ViewState from;
  final FrictionSimulation _x, _y;

  @override
  ViewState at(Duration t) {
    final s = t.inMicroseconds / 1e6;
    return ViewState(x: _x.x(s), y: _y.x(s), zoom: from.zoom);
  }

  @override
  bool isDone(Duration t) {
    final s = t.inMicroseconds / 1e6;
    return _x.isDone(s) && _y.isDone(s);
  }
}
