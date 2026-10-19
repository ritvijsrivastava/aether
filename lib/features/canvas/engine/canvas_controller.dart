import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/physics.dart' show FrictionSimulation;
import 'package:flutter/scheduler.dart';

import '../input/input_arbiter.dart';
import 'scene.dart';
import 'view_state.dart';

/// Owns the canvas view and scene and implements the gestures the arbiter
/// asks for. Painters listen to [view] and [scene] directly, so a pan or a
/// card drag repaints layers without rebuilding any widget.
class CanvasController implements GestureSink {
  CanvasController({required Scene scene, ViewState view = const ViewState()})
    : scene = ValueNotifier<Scene>(scene),
      view = ValueNotifier<ViewState>(view);

  final ValueNotifier<Scene> scene;
  final ValueNotifier<ViewState> view;

  /// Size of the canvas surface in logical px; set by the view on layout.
  Size viewport = Size.zero;

  /// Screen area covered by floating controls; "fit" centres in what is left.
  EdgeInsets insets = EdgeInsets.zero;

  /// While true, a change in the viewport's size re-fits the first page. A
  /// document can open while the soft keyboard is still folding away, so the
  /// first fit is made for a screen that then grows; this redoes it. Set by
  /// [fitFirst] and cleared by anything the user does.
  bool refitOnResize = false;

  /// Called after a card drag ends, with the card and its total world shift.
  void Function(String cardId, Offset delta)? onCardMoved;

  Ticker? _ticker;
  _Motion? _motion;
  String? _dragging;
  Offset _dragTotal = Offset.zero;

  /// Must be called once with the widget's [TickerProvider].
  void attach(TickerProvider vsync) {
    _ticker ??= vsync.createTicker(_tick);
  }

  void dispose() {
    _ticker?.dispose();
    scene.dispose();
    view.dispose();
  }

  bool get isAnimating => _motion != null;

  // --- view mutation -------------------------------------------------------

  void _set(ViewState v) {
    view.value = v.clamped(viewport, scene.value.bounds);
  }

  void setView(ViewState v) {
    _stop();
    _set(v);
  }

  @override
  void gestureStart() {
    refitOnResize = false;
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

  // --- card drag -----------------------------------------------------------

  @override
  void cardDragStart(String cardId) {
    refitOnResize = false;
    _dragging = cardId;
    _dragTotal = Offset.zero;
  }

  @override
  void cardDragBy(Offset delta) {
    final id = _dragging;
    if (id == null) return;
    final world = delta / view.value.zoom;
    _dragTotal += world;
    scene.value = scene.value.withCardMoved(id, world);
  }

  @override
  void cardDragEnd() {
    final id = _dragging;
    _dragging = null;
    if (id != null && _dragTotal != Offset.zero) {
      onCardMoved?.call(id, _dragTotal);
    }
  }

  // --- zoom and fit ---------------------------------------------------------

  /// The centre of the area not covered by floating controls.
  Offset get _focus => Offset(
    insets.left + (viewport.width - insets.horizontal) / 2,
    insets.top + (viewport.height - insets.vertical) / 2,
  );

  void zoomBy(double factor, {bool animate = true}) {
    refitOnResize = false;
    final target = view.value.zoomAt(_focus, factor);
    animate ? animateTo(target) : setView(target);
  }

  void zoomTo(double zoom) {
    refitOnResize = false;
    animateTo(
      view.value.withZoomAt(
        _focus,
        zoom.clamp(ViewState.minZoom, ViewState.maxZoom),
      ),
    );
  }

  /// Fit the page nearest the centre of the screen.
  void fitPage({bool animate = true}) {
    refitOnResize = false;
    final s = scene.value;
    if (s.isEmpty || viewport.isEmpty) return;
    final here = view.value.screenToWorld(_focus);
    final card = s.nearest(here)!;
    final target = ViewState.fitRect(card.rect, viewport, insets: insets);
    animate ? animateTo(target) : setView(target);
  }

  /// Centre the first page, at fit zoom. Used when a document opens.
  void fitFirst() {
    final s = scene.value;
    if (s.isEmpty || viewport.isEmpty) return;
    setView(ViewState.fitRect(s.cards.first.rect, viewport, insets: insets));
    refitOnResize = true;
  }

  void animateTo(
    ViewState target, {
    Duration duration = const Duration(milliseconds: 240),
  }) {
    final clamped = target.clamped(viewport, scene.value.bounds);
    if (clamped == view.value) return;
    _motion = _Tween(view.value, clamped, duration);
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
    final next = m.at(elapsed);
    final clamped = next.clamped(viewport, scene.value.bounds);
    view.value = clamped;
    // A fling that runs into the edge stops there instead of grinding on.
    final hitEdge = m is _Fling && (clamped.x != next.x || clamped.y != next.y);
    if (m.isDone(elapsed) || hitEdge) _stop();
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
