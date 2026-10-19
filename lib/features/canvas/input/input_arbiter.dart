import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

/// One pointer event, reduced to what the arbiter needs.
@immutable
class PointerSample {
  const PointerSample({
    required this.id,
    required this.kind,
    required this.position,
    required this.time,
    this.buttons = 0,
    this.radiusMajor = 0,
  });

  final int id;
  final PointerDeviceKind kind;
  final Offset position;
  final Duration time;
  final int buttons;
  final double radiusMajor;
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
  void cardDragStart(String cardId);
  void cardDragBy(Offset delta);
  void cardDragEnd();
}

/// Live facts the arbiter needs on every event.
abstract interface class ArbiterContext {
  /// The Pan tool is active.
  bool get panTool;

  /// Space is held (temporary pan).
  bool get spaceHeld;

  /// Settings: a finger also applies the active tool. Off by default.
  bool get fingerDraws;

  /// The card whose drag handle is under [screen], if any.
  String? handleAt(Offset screen);
}

/// Turns raw pointer events into canvas gestures.
///
/// Rules (SPEC §7): a finger pans and pinches, never marks; a handle drags
/// its card for any pointer; mouse and pen pan only under the Pan tool,
/// Space or the middle button; and touches are ignored while a pen is near
/// (palm rejection safety net, the OS does the real work).
///
/// Pure logic: events in, [GestureSink] calls out.
class InputArbiter {
  InputArbiter(this.sink, this.context);

  final GestureSink sink;
  final ArbiterContext context;

  /// Touches ignored for this long after the pen was last seen.
  static const Duration penLockout = Duration(milliseconds: 250);

  /// Touch contacts larger than this (logical px) are palms.
  static const double palmRadius = 24;

  static const int _middleButton = 4;
  static const int _primaryButton = 1;

  _Mode _mode = _Mode.idle;
  final Map<int, Offset> _touches = {};
  final Set<int> _ignored = {};
  int? _lead; // pointer driving pan / cardDrag
  Offset _last = Offset.zero;
  Offset _pinchCentroid = Offset.zero;
  double _pinchDistance = 1;
  bool _penDown = false;
  Duration? _penSeen;
  final _velocity = _Velocity();

  // Trackpad pan/zoom (Linux).
  Offset _tpPan = Offset.zero;
  double _tpScale = 1;

  bool _penNear(Duration now) =>
      _penDown || (_penSeen != null && now - _penSeen! < penLockout);

  void hover(PointerSample p) {
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penSeen = p.time;
    }
  }

  void down(PointerSample p) {
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penDown = true;
      _penSeen = p.time;
      // A pen landing cancels a finger gesture it interrupted.
      if (_mode == _Mode.pan || _mode == _Mode.pinch) {
        _ignored.addAll(_touches.keys);
        _touches.clear();
        _finish(Offset.zero);
      }
    }

    // A handle drags its card, whatever dragged it.
    final handle = context.handleAt(p.position);
    if (handle != null && _mode == _Mode.idle && _acceptable(p)) {
      _mode = _Mode.cardDrag;
      _lead = p.id;
      _last = p.position;
      sink.gestureStart();
      sink.cardDragStart(handle);
      return;
    }

    switch (p.kind) {
      case PointerDeviceKind.touch:
        if (_penNear(p.time) || p.radiusMajor > palmRadius) {
          _ignored.add(p.id);
          return;
        }
        if (_mode == _Mode.cardDrag) {
          _ignored.add(p.id);
          return;
        }
        if (!_touchPans) {
          // Finger-draws is on: a single finger belongs to the tool, but two
          // fingers still pinch. (No tool consumes it before M3.)
          _touches[p.id] = p.position;
          if (_touches.length == 2) _beginPinch();
          return;
        }
        _touches[p.id] = p.position;
        if (_touches.length == 1) {
          _beginPan(p);
        } else if (_touches.length == 2) {
          _beginPinch();
        }
      case PointerDeviceKind.mouse:
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
      case PointerDeviceKind.trackpad:
      case PointerDeviceKind.unknown:
        if (_mode != _Mode.idle) return;
        final middle = p.buttons & _middleButton != 0;
        final primary =
            p.buttons & _primaryButton != 0 ||
            p.kind == PointerDeviceKind.stylus;
        if (middle || (primary && (context.panTool || context.spaceHeld))) {
          _beginPan(p);
        }
    }
  }

  void move(PointerSample p) {
    if (_ignored.contains(p.id)) return;
    switch (_mode) {
      case _Mode.pan:
        if (p.id != _lead) return;
        final d = p.position - _last;
        _last = p.position;
        _velocity.add(p.time, p.position);
        if (d != Offset.zero) sink.panBy(d);
      case _Mode.cardDrag:
        if (p.id != _lead) return;
        final d = p.position - _last;
        _last = p.position;
        if (d != Offset.zero) sink.cardDragBy(d);
      case _Mode.pinch:
        if (!_touches.containsKey(p.id)) return;
        _touches[p.id] = p.position;
        if (_touches.length < 2) return;
        final (c, d) = _pinchMetrics();
        final factor = _pinchDistance == 0 ? 1.0 : d / _pinchDistance;
        sink.zoomPan(anchor: c, factor: factor, pan: c - _pinchCentroid);
        _pinchCentroid = c;
        _pinchDistance = d == 0 ? 1 : d;
      case _Mode.idle:
        if (_touches.containsKey(p.id)) _touches[p.id] = p.position;
    }
  }

  void up(PointerSample p) {
    final wasIgnored = _ignored.remove(p.id);
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penDown = false;
      _penSeen = p.time;
    }
    if (wasIgnored) return;
    _touches.remove(p.id);
    switch (_mode) {
      case _Mode.pan:
        if (p.id != _lead) return;
        _velocity.add(p.time, p.position);
        final fling = p.kind == PointerDeviceKind.touch
            ? _velocity.estimate()
            : Offset.zero;
        _finish(fling);
      case _Mode.cardDrag:
        if (p.id != _lead) return;
        _finish(Offset.zero);
      case _Mode.pinch:
        if (_touches.length == 1) {
          // One finger left: carry on panning with it, no fling.
          final id = _touches.keys.single;
          _mode = _Mode.pan;
          _lead = id;
          _last = _touches[id]!;
          _velocity.reset();
        } else if (_touches.isEmpty) {
          _finish(Offset.zero);
        }
      case _Mode.idle:
        break;
    }
  }

  void cancel(PointerSample p) {
    _ignored.remove(p.id);
    if (p.kind == PointerDeviceKind.stylus) _penDown = false;
    _touches.remove(p.id);
    if (_mode == _Mode.pinch && _touches.length == 1) {
      up(p);
      return;
    }
    if ((_mode == _Mode.pan || _mode == _Mode.cardDrag) && p.id == _lead) {
      _finish(Offset.zero);
    } else if (_touches.isEmpty && _mode == _Mode.pinch) {
      _finish(Offset.zero);
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

  bool get _touchPans =>
      !context.fingerDraws || context.panTool || context.spaceHeld;

  bool _acceptable(PointerSample p) =>
      p.kind != PointerDeviceKind.touch ||
      (!_penNear(p.time) && p.radiusMajor <= palmRadius);

  void _beginPan(PointerSample p) {
    _mode = _Mode.pan;
    _lead = p.id;
    _last = p.position;
    _velocity
      ..reset()
      ..add(p.time, p.position);
    sink.gestureStart();
  }

  void _beginPinch() {
    _mode = _Mode.pinch;
    final (c, d) = _pinchMetrics();
    _pinchCentroid = c;
    _pinchDistance = d == 0 ? 1 : d;
    sink.gestureStart();
  }

  (Offset, double) _pinchMetrics() {
    final pts = _touches.values.take(2).toList();
    final c = (pts[0] + pts[1]) / 2;
    return (c, (pts[0] - pts[1]).distance);
  }

  void _finish(Offset fling) {
    final m = _mode;
    _mode = _Mode.idle;
    _lead = null;
    if (m == _Mode.cardDrag) {
      sink.cardDragEnd();
    } else if (m == _Mode.pan || m == _Mode.pinch) {
      sink.panEnd(fling);
    }
  }
}

enum _Mode { idle, pan, pinch, cardDrag }

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
