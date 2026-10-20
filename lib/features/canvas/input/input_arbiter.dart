import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show ChangeNotifier;
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
    this.radiusMajor = 0,
    this.pressure,
  });

  final int id;
  final PointerDeviceKind kind;
  final Offset position;
  final Duration time;
  final int buttons;
  final double radiusMajor;

  /// 0 to 1, or null if the device reports no pressure.
  final double? pressure;
}

/// What the arbiter has seen of touch contacts, for the performance overlay:
/// how big fingers and palms really are on this device, and how many contacts
/// were set aside as palms.
class TouchStats extends ChangeNotifier {
  double lastRadius = 0, maxFingerRadius = 0, maxPalmRadius = 0;
  int fingers = 0, palms = 0;
  String lastVerdict = '';

  void finger(double radius) {
    fingers++;
    lastRadius = radius;
    if (radius > maxFingerRadius) maxFingerRadius = radius;
    lastVerdict = 'finger';
  }

  void palm(double radius, String why) {
    palms++;
    lastRadius = radius;
    if (radius > maxPalmRadius) maxPalmRadius = radius;
    lastVerdict = 'palm ($why)';
  }

  void changed() => notifyListeners();

  String? get line => fingers + palms == 0
      ? null
      : 'touch: last ${lastRadius.toStringAsFixed(0)} px, $lastVerdict'
            ' · fingers $fingers (max ${maxFingerRadius.toStringAsFixed(0)})'
            ' · palms $palms (max ${maxPalmRadius.toStringAsFixed(0)})';
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

  /// A tool's drag (Mark, Ink, Erase, ...): see [ToolGestures]. [tool] is the
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

  /// Settings: a finger also applies the active tool. Off by default.
  bool get fingerDraws;

  /// The card whose drag handle is under [screen], if any.
  String? handleAt(Offset screen);
}

/// Turns raw pointer events into canvas gestures.
///
/// Rules (SPEC §7): a finger pans and pinches, never marks (unless "finger
/// draws" is on); a handle drags its card for any pointer; mouse and pen pan
/// only under the Pan tool, Space or the middle button, and otherwise apply
/// the active tool (the pen's eraser end or barrel button means Erase for
/// that stroke); and touches are ignored while a pen is near (palm
/// rejection safety net, the OS does the real work).
///
/// Pure logic: events in, [GestureSink] calls out.
class InputArbiter {
  InputArbiter(this.sink, this.context, {this.stats});

  final GestureSink sink;
  final ArbiterContext context;
  final TouchStats? stats;

  /// A touch this soon after the pen was last seen, and this close to it, is
  /// the hand that holds the pen. A touch farther away is the other hand.
  static const Duration penLockout = Duration(milliseconds: 250);
  static const double palmZone = 300;

  /// A contact that has stayed put this long (and under [restingSlop] px) when
  /// a second finger lands is a resting hand, not half of a pinch.
  static const Duration restingTime = Duration(milliseconds: 600);
  static const double restingSlop = 8;

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
  Offset? _penPos;
  final Map<int, Duration> _downAt = {};
  final Map<int, double> _travel = {};
  final _velocity = _Velocity();

  // Trackpad pan/zoom (Linux).
  Offset _tpPan = Offset.zero;
  double _tpScale = 1;

  bool _penNear(Duration now) =>
      _penDown || (_penSeen != null && now - _penSeen! < penLockout);

  /// Why [p] (a touch) is a palm, or null if it is a finger.
  ///
  /// A palm is set aside on its own: it never cancels, blocks or joins the
  /// fingers that are doing something.
  String? _palmReason(PointerSample p) {
    if (p.radiusMajor > palmRadius) return 'large';
    if (_penDown) return 'pen down';
    if (_penNear(p.time)) {
      final at = _penPos;
      if (at == null || (p.position - at).distance <= palmZone) {
        return 'by the pen';
      }
    }
    return null;
  }

  void hover(PointerSample p) {
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penSeen = p.time;
      _penPos = p.position;
    }
  }

  void down(PointerSample p) {
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penDown = true;
      _penSeen = p.time;
      _penPos = p.position;
      // A pen landing cancels a finger gesture it interrupted.
      if (_mode == _Mode.pan || _mode == _Mode.pinch) {
        _ignored.addAll(_touches.keys);
        _touches.clear();
        _finish(Offset.zero);
      } else if (_mode == _Mode.tool && _touches.containsKey(_lead)) {
        _ignored.addAll(_touches.keys);
        _touches.clear();
        _endTool(cancel: true);
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
        final palm = _palmReason(p);
        if (palm != null) {
          _ignored.add(p.id);
          stats?.palm(p.radiusMajor, palm);
          stats?.changed();
          return;
        }
        stats?.finger(p.radiusMajor);
        stats?.changed();
        _downAt[p.id] = p.time;
        _travel[p.id] = 0;
        if (_mode == _Mode.cardDrag) {
          _ignored.add(p.id);
          return;
        }
        if (!_touchPans) {
          // Finger-draws is on: a single finger belongs to the tool, but two
          // fingers still pinch.
          _touches[p.id] = p.position;
          if (_touches.length == 1 && context.tool != CanvasTool.pan) {
            _beginTool(p, context.tool);
          } else if (_touches.length == 2) {
            if (_mode == _Mode.tool) _endTool(cancel: true);
            _beginPinch();
          }
          return;
        }
        if (_touches.length == 1 &&
            _mode == _Mode.pan &&
            _restingLead(p.time)) {
          // The first contact has been resting: a hand, not half a pinch.
          // Set it aside and let this finger pan.
          final resting = _touches.keys.single;
          _ignored.add(resting);
          _touches.clear();
          stats?.palm(0, 'resting');
          stats?.changed();
          _finish(Offset.zero);
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
        // Bit 4 is the middle mouse button, but on a pen it is a barrel button.
        final isPen =
            p.kind == PointerDeviceKind.stylus ||
            p.kind == PointerDeviceKind.invertedStylus;
        final middle = !isPen && p.buttons & _middleButton != 0;
        final primary =
            p.buttons & _primaryButton != 0 ||
            p.kind == PointerDeviceKind.stylus ||
            p.kind == PointerDeviceKind.invertedStylus;
        final tool = context.pen.resolveTool(context.tool, p.kind, p.buttons);
        if (middle ||
            (primary && (tool == CanvasTool.pan || context.spaceHeld))) {
          _beginPan(p);
        } else if (primary) {
          _beginTool(p, tool);
        }
    }
  }

  bool _restingLead(Duration now) {
    if (_touches.length != 1) return false;
    final id = _touches.keys.single;
    final since = _downAt[id];
    return since != null &&
        now - since >= restingTime &&
        (_travel[id] ?? 0) <= restingSlop;
  }

  void move(PointerSample p) {
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penSeen = p.time;
      _penPos = p.position;
    }
    final before = _touches[p.id];
    if (before != null) {
      _travel[p.id] = (_travel[p.id] ?? 0) + (p.position - before).distance;
    }
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
      case _Mode.tool:
        if (p.id != _lead) return;
        if (_touches.containsKey(p.id)) _touches[p.id] = p.position;
        _lastPoint = _point(p);
        sink.toolMove(_lastPoint!);
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
    _downAt.remove(p.id);
    _travel.remove(p.id);
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
      case _Mode.tool:
        if (p.id != _lead) return;
        _endTool(at: p);
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
    _downAt.remove(p.id);
    _travel.remove(p.id);
    if (p.kind == PointerDeviceKind.stylus) _penDown = false;
    _touches.remove(p.id);
    if (_mode == _Mode.pinch && _touches.length == 1) {
      up(p);
      return;
    }
    if (_mode == _Mode.tool && p.id == _lead) {
      _endTool(cancel: true);
    } else if ((_mode == _Mode.pan || _mode == _Mode.cardDrag) &&
        p.id == _lead) {
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

  /// Escape: drop a mark in progress without making it.
  void escape() {
    if (_mode == _Mode.tool) _endTool(cancel: true);
  }

  bool get _touchPans =>
      !context.fingerDraws ||
      context.tool == CanvasTool.pan ||
      context.spaceHeld;

  bool _acceptable(PointerSample p) =>
      p.kind != PointerDeviceKind.touch || _palmReason(p) == null;

  void _beginPan(PointerSample p) {
    _mode = _Mode.pan;
    _lead = p.id;
    _last = p.position;
    _velocity
      ..reset()
      ..add(p.time, p.position);
    sink.gestureStart();
  }

  ToolPoint? _lastPoint;

  ToolPoint _point(PointerSample p) => ToolPoint(
    position: p.position,
    time: p.time,
    kind: p.kind,
    pressure: p.pressure,
  );

  void _beginTool(PointerSample p, CanvasTool tool) {
    _mode = _Mode.tool;
    _lead = p.id;
    _last = p.position;
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

enum _Mode { idle, pan, pinch, cardDrag, tool }

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
