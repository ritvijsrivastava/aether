import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

import '../canvas_ui_state.dart';
import 'pen_config.dart';
import 'tool_gestures.dart';

/// One pointer event, reduced to what the arbiter needs.
@immutable
class PointerSample {
  const PointerSample({
    required this.id,
    required this.kind,
    required this.position,
    required this.time,
    this.buttons = 0,
    this.pressure,
  });

  final int id;
  final PointerDeviceKind kind;
  final Offset position;
  final Duration time;
  final int buttons;

  /// 0 to 1, or null if the device reports no pressure.
  final double? pressure;
}

/// What the arbiter asks the canvas to do. All offsets are screen space.
abstract interface class GestureSink {
  /// A new gesture starts: stop any fling or animation in progress.
  void gestureStart();
  void panBy(Offset delta);

  /// Zoom by [factor] about [anchor] and pan by [pan] in one step.
  void zoomPan({
    required Offset anchor,
    required double factor,
    required Offset pan,
  });

  /// A pan ended; [velocity] is in px/s (zero for no fling).
  void panEnd(Offset velocity);

  /// A tool's drag (Ink, Erase, Select): see [ToolGestures]. [tool] is the
  /// tool the pointer applies, which the pen may have switched to Erase.
  void toolStart(CanvasTool tool, ToolPoint p);
  void toolMove(ToolPoint p);
  void toolEnd(ToolPoint p);
  void toolCancel();
}

/// Live facts the arbiter needs on every event.
abstract interface class ArbiterContext {
  /// The tool chosen in the tool rail.
  CanvasTool get tool;

  /// Pen quirks and preferences (button bits, pressure curve).
  PenConfig get pen;

  /// Space is held (temporary pan).
  bool get spaceHeld;
}

/// Turns raw pointer events into canvas gestures. Three rules:
///
/// 1. A **stylus** (or mouse) applies the active tool; its eraser end or
///    barrel button means Erase for that stroke. Under the Pan tool it pans.
/// 2. **One finger** pans, **two fingers** pinch-zoom (and pan). A finger
///    never draws. While the stylus is down, fingers are ignored.
/// 3. The mouse wheel pans, Ctrl+wheel zooms, a touchpad pans and zooms;
///    Space+drag or the middle button pans.
///
/// Pure logic: events in, [GestureSink] calls out.
class InputArbiter {
  InputArbiter(this.sink, this.context);

  final GestureSink sink;
  final ArbiterContext context;

  static const int _middleButton = 4;
  static const int _primaryButton = 1;

  _Mode _mode = _Mode.idle;
  int? _lead; // the pointer driving a pan or a tool drag
  Offset _last = Offset.zero;
  ToolPoint? _lastPoint;
  final Map<int, Offset> _touches = {};
  final Set<int> _ignored = {};
  bool _penDown = false;
  final List<int> _pair = [];
  Offset _pinchCentroid = Offset.zero;
  double _pinchDistance = 1;
  final _velocity = _Velocity();

  // Trackpad pan/zoom (Linux).
  Offset _tpPan = Offset.zero;
  double _tpScale = 1;

  static bool _isPen(PointerDeviceKind k) =>
      k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus;

  /// Hovering does nothing; kept so the view can report it without caring.
  void hover(PointerSample p) {}

  void down(PointerSample p) {
    if (p.kind == PointerDeviceKind.touch) {
      _touchDown(p);
      return;
    }
    if (_isPen(p.kind)) {
      _penDown = true;
      // The pen takes over from any finger gesture in progress.
      if (_mode == _Mode.pan || _mode == _Mode.pinch) {
        _ignored.addAll(_touches.keys);
        _touches.clear();
        _pair.clear();
        _finish(Offset.zero);
      }
    }
    if (_mode != _Mode.idle) return;
    // Bit 4 is the middle mouse button, but on a pen it is a barrel button.
    final middle = !_isPen(p.kind) && p.buttons & _middleButton != 0;
    final primary = p.buttons & _primaryButton != 0 || _isPen(p.kind);
    final tool = context.pen.resolveTool(context.tool, p.kind, p.buttons);
    if (middle || (primary && (tool == CanvasTool.pan || context.spaceHeld))) {
      _beginPan(p);
    } else if (primary) {
      _beginTool(p, tool);
    }
  }

  void _touchDown(PointerSample p) {
    if (_penDown || _mode == _Mode.tool) {
      _ignored.add(p.id);
      return;
    }
    _touches[p.id] = p.position;
    if (_touches.length == 1) {
      _beginPan(p);
    } else if (_touches.length == 2) {
      _beginPinch();
    } else {
      _ignored.add(p.id);
      _touches.remove(p.id);
    }
  }

  void move(PointerSample p) {
    if (_ignored.contains(p.id)) return;
    switch (_mode) {
      case _Mode.pan:
        if (p.id != _lead) return;
        if (_touches.containsKey(p.id)) _touches[p.id] = p.position;
        final d = p.position - _last;
        _last = p.position;
        _velocity.add(p.time, p.position);
        if (d != Offset.zero) sink.panBy(d);
      case _Mode.pinch:
        if (!_touches.containsKey(p.id)) return;
        _touches[p.id] = p.position;
        _applyPinch();
      case _Mode.tool:
        if (p.id != _lead) return;
        _lastPoint = _point(p);
        sink.toolMove(_lastPoint!);
      case _Mode.idle:
        break;
    }
  }

  void up(PointerSample p) {
    if (_isPen(p.kind)) _penDown = false;
    if (_ignored.remove(p.id)) return;
    _lift(p, cancelled: false);
  }

  void cancel(PointerSample p) {
    if (_isPen(p.kind)) _penDown = false;
    if (_ignored.remove(p.id)) return;
    _lift(p, cancelled: true);
  }

  void _lift(PointerSample p, {required bool cancelled}) {
    final wasTouch = _touches.remove(p.id) != null;
    switch (_mode) {
      case _Mode.pan:
        if (p.id != _lead) return;
        _velocity.add(p.time, p.position);
        final fling = !cancelled && p.kind == PointerDeviceKind.touch
            ? _velocity.estimate()
            : Offset.zero;
        _finish(fling);
      case _Mode.pinch:
        if (!wasTouch || !_pair.contains(p.id)) return;
        _pair.remove(p.id);
        if (_touches.isNotEmpty) {
          // One of the pair left: carry on panning with a finger still down.
          final id = _touches.keys.first;
          _mode = _Mode.pan;
          _lead = id;
          _last = _touches[id]!;
          _velocity.reset();
        } else {
          _finish(Offset.zero);
        }
      case _Mode.tool:
        if (p.id != _lead) return;
        if (cancelled) {
          _endTool(cancel: true);
        } else {
          _endTool(at: p);
        }
      case _Mode.idle:
        break;
    }
  }

  /// Mouse wheel / scroll. Ctrl zooms about [position]; otherwise it pans.
  void scroll(Offset position, Offset delta, {required bool ctrl}) {
    sink.gestureStart();
    if (ctrl) {
      sink.zoomPan(
        anchor: position,
        factor: math.exp(-delta.dy * 0.01),
        pan: Offset.zero,
      );
    } else {
      sink.panBy(-delta);
    }
  }

  void panZoomStart() {
    _tpPan = Offset.zero;
    _tpScale = 1;
    sink.gestureStart();
  }

  /// [pan] and [scale] are cumulative since [panZoomStart].
  void panZoomUpdate(Offset position, Offset pan, double scale) {
    sink.zoomPan(
      anchor: position,
      factor: _tpScale == 0 ? 1 : scale / _tpScale,
      pan: pan - _tpPan,
    );
    _tpPan = pan;
    _tpScale = scale;
  }

  void panZoomEnd() => sink.panEnd(Offset.zero);

  /// Escape: drop a stroke in progress without making it.
  void escape() {
    if (_mode == _Mode.tool) _endTool(cancel: true);
  }

  void _beginPan(PointerSample p) {
    _mode = _Mode.pan;
    _lead = p.id;
    _last = p.position;
    _velocity
      ..reset()
      ..add(p.time, p.position);
    sink.gestureStart();
  }

  ToolPoint _point(PointerSample p) => ToolPoint(
    position: p.position,
    time: p.time,
    kind: p.kind,
    pressure: p.pressure,
  );

  void _beginTool(PointerSample p, CanvasTool tool) {
    _mode = _Mode.tool;
    _lead = p.id;
    _lastPoint = _point(p);
    sink.gestureStart();
    sink.toolStart(tool, _lastPoint!);
  }

  /// Ends the tool drag: at [at] normally, or abandoned if [cancel].
  void _endTool({PointerSample? at, bool cancel = false}) {
    final end = at == null ? _lastPoint : _point(at);
    _mode = _Mode.idle;
    _lead = null;
    if (cancel || end == null) {
      sink.toolCancel();
    } else {
      sink.toolEnd(end);
    }
  }

  void _beginPinch() {
    _mode = _Mode.pinch;
    _pair
      ..clear()
      ..addAll(_touches.keys.take(2));
    final (c, d) = _pinchMetrics();
    _pinchCentroid = c;
    _pinchDistance = d == 0 ? 1 : d;
    sink.gestureStart();
  }

  void _applyPinch() {
    if (_pair.length < 2) return;
    final (c, d) = _pinchMetrics();
    final factor = d / _pinchDistance;
    sink.zoomPan(anchor: c, factor: factor, pan: c - _pinchCentroid);
    _pinchCentroid = c;
    _pinchDistance = d == 0 ? 1 : d;
  }

  (Offset, double) _pinchMetrics() {
    final pts = [for (final id in _pair) _touches[id]!];
    return ((pts[0] + pts[1]) / 2, (pts[0] - pts[1]).distance);
  }

  void _finish(Offset fling) {
    final m = _mode;
    _mode = _Mode.idle;
    _lead = null;
    if (m == _Mode.pan || m == _Mode.pinch) sink.panEnd(fling);
  }
}

enum _Mode { idle, pan, pinch, tool }

/// Velocity from the last ~100 ms of samples.
class _Velocity {
  static const Duration window = Duration(milliseconds: 100);
  static const double maxSpeed = 8000;
  final List<(Duration, Offset)> _s = [];

  void reset() => _s.clear();

  void add(Duration t, Offset p) {
    _s.add((t, p));
    while (_s.length > 2 && t - _s.first.$1 > window) {
      _s.removeAt(0);
    }
  }

  Offset estimate() {
    if (_s.length < 2) return Offset.zero;
    final dt = (_s.last.$1 - _s.first.$1).inMicroseconds / 1e6;
    if (dt <= 0) return Offset.zero;
    var v = (_s.last.$2 - _s.first.$2) / dt;
    if (v.distance > maxSpeed) v = v / v.distance * maxSpeed;
    return v;
  }
}
