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

  // --- touch log: the last [logWindow] of raw events, for finding out why a
  // palm does what it does (Settings, Diagnostics, Record touch log). ---

  bool recording = false;
  static const Duration logWindow = Duration(seconds: 20);
  final List<(Duration, String)> _log = [];
  bool logDirty = false;

  void record(String phase, PointerSample p) {
    if (!recording) return;
    _log.add((
      p.time,
      '${p.time.inMilliseconds} #${p.id} ${p.kind.name} $phase '
          '${p.position.dx.toStringAsFixed(0)},${p.position.dy.toStringAsFixed(0)} '
          'r=${p.radiusMajor.toStringAsFixed(1)}'
          '${p.pressure == null ? '' : ' p=${p.pressure!.toStringAsFixed(2)}'}',
    ));
    while (_log.isNotEmpty && p.time - _log.first.$1 > logWindow) {
      _log.removeAt(0);
    }
    logDirty = true;
  }

  /// The recorded events, oldest first, one per line, with a header.
  String dumpLog() =>
      '# ms #pointer kind phase x,y radius [pressure]\n'
      '${_log.map((e) => e.$2).join('\n')}\n';

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

  /// A contact drives a pan or pinch only once it has moved this far within
  /// this time. A resting palm jitters; a finger pan does not.
  static const double moveSlop = 10;
  static const Duration moveWindow = Duration(milliseconds: 150);

  /// Two fingers that land this close together are a deliberate pair (one may
  /// stay still while the other moves: a pinch). A contact that was already
  /// there for longer is a resting hand and never pairs.
  static const Duration pairWindow = Duration(milliseconds: 300);

  /// A lone contact (not part of a pair) that has stayed put this long while
  /// another finger was down is a resting hand; if it then slides, it is
  /// still set aside rather than allowed to pan.
  static const Duration restingTime = Duration(milliseconds: 600);

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
  final Map<int, List<(Duration, Offset)>> _trail = {};
  final Set<int> _pinchIds = {};
  final Map<int, Duration> _landed = {};
  final Map<int, int> _partner = {};
  final Map<int, Offset> _origin = {};
  final Map<int, double> _drift = {};
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
    stats?.record('hover', p);
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penSeen = p.time;
      _penPos = p.position;
    }
  }

  void down(PointerSample p) {
    stats?.record('down', p);
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
        // A finger that has only landed does nothing yet: pan and pinch are
        // driven by contacts that MOVE, so a hand resting beside the fingers
        // (whatever its size) can never block or join them.
        // Landing within [pairWindow] of another finger makes a pair.
        for (final e in _landed.entries) {
          if (_touches.containsKey(e.key) &&
              !_partner.containsKey(e.key) &&
              p.time - e.value <= pairWindow) {
            _partner[e.key] = p.id;
            _partner[p.id] = e.key;
            break;
          }
        }
        _landed[p.id] = p.time;
        _origin[p.id] = p.position;
        _drift[p.id] = 0;
        _touches[p.id] = p.position;
        _trail[p.id] = [(p.time, p.position)];
        if (_touches.length == 1 && _mode == _Mode.idle) {
          sink.gestureStart(); // stops a fling
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

  /// Contacts that have moved at least [moveSlop] px over the last
  /// [moveWindow] (or since their previous sample, if that was longer ago).
  bool _isMoving(int id) => _movement(id) >= moveSlop;

  double _movement(int id) {
    final pos = _touches[id];
    if (pos == null || (_trail[id]?.length ?? 0) < 2) return 0;
    return (pos - _trailStart(id)).distance;
  }

  /// Where [id] was about [moveWindow] ago (or at its previous sample): the
  /// place a pan that starts now counts from, so the first 10 px are not lost.
  Offset _trailStart(int id) {
    final t = _trail[id]!;
    final now = t.last.$1;
    var ref = t.length >= 2 ? t[t.length - 2].$2 : t.last.$2;
    for (var i = 0; i < t.length - 1; i++) {
      if (now - t[i].$1 <= moveWindow) {
        ref = t[i].$2;
        break;
      }
    }
    return ref;
  }

  void _noteTrail(PointerSample p) {
    final t = _trail[p.id];
    if (t == null) return;
    t.add((p.time, p.position));
    while (t.length > 2 && p.time - t[1].$1 > moveWindow * 3) {
      t.removeAt(0);
    }
  }

  /// A contact that has sat still for [restingTime] with another finger down,
  /// and has just begun to move: a hand sliding, not a finger.
  bool _isRestingHand(PointerSample p) {
    final land = _landed[p.id];
    final o = _origin[p.id];
    if (land == null || o == null || !_touches.containsKey(p.id)) return false;
    if (_touches.length < 2 || _pairOf(p.id) != null) return false;
    if (p.time - land < restingTime) return false;
    if ((_drift[p.id] ?? 0) >= moveSlop) return false;
    return (p.position - o).distance >= moveSlop;
  }

  /// The finger [id] landed together with, if it is still down.
  int? _pairOf(int id) {
    final other = _partner[id];
    return other != null && _touches.containsKey(other) ? other : null;
  }

  void _forget(int id) {
    _trail.remove(id);
    _landed.remove(id);
    _origin.remove(id);
    _drift.remove(id);
    final other = _partner.remove(id);
    if (other != null) _partner.remove(other);
  }

  /// With nothing in progress, starts a pan or pinch if contacts are moving.
  void _maybeBegin(Duration now) {
    final moving = [
      for (final id in _touches.keys)
        if (_isMoving(id)) id,
    ]..sort((a, b) => _movement(b).compareTo(_movement(a)));
    if (moving.isEmpty) return;
    if (moving.length == 1 && _pairOf(moving.single) != null) {
      _beginPinch([moving.single, _pairOf(moving.single)!], {moving.single});
    } else if (moving.length == 1) {
      final id = moving.single;
      final from = _trailStart(id);
      _mode = _Mode.pan;
      _lead = id;
      _velocity
        ..reset()
        ..add(now, from);
      sink.gestureStart();
      final d = _touches[id]! - from;
      _last = _touches[id]!;
      _velocity.add(now, _last);
      if (d != Offset.zero) sink.panBy(d);
    } else {
      final two = moving.take(2).toList();
      _beginPinch(two, {...two});
    }
  }

  void move(PointerSample p) {
    stats?.record('move', p);
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penSeen = p.time;
      _penPos = p.position;
    }
    if (_ignored.contains(p.id)) return;
    if (_touchPans && _isRestingHand(p)) {
      _ignored.add(p.id);
      _touches.remove(p.id);
      _forget(p.id);
      stats?.palm(p.radiusMajor, 'resting hand slid');
      stats?.changed();
      return;
    }
    if (_touches.containsKey(p.id)) {
      final o = _origin[p.id];
      if (o != null) {
        final d = (p.position - o).distance;
        if (d > (_drift[p.id] ?? 0)) _drift[p.id] = d;
      }
    }
    switch (_mode) {
      case _Mode.pan:
        if (_touches.containsKey(p.id)) {
          _touches[p.id] = p.position;
          _noteTrail(p);
        }
        if (p.id != _lead) {
          // Another contact: it joins only if it is really moving.
          if (_touches.containsKey(p.id) && _isMoving(p.id)) {
            _beginPinch([_lead!, p.id], {p.id});
          }
          return;
        }
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
        if (!_pinchIds.contains(p.id) || _pinchIds.length < 2) return;
        _applyPinch();
      case _Mode.idle:
        if (_touches.containsKey(p.id)) {
          _touches[p.id] = p.position;
          _noteTrail(p);
          if (_touchPans) _maybeBegin(p.time);
        }
    }
  }

  void up(PointerSample p) {
    stats?.record('up', p);
    final wasIgnored = _ignored.remove(p.id);
    _forget(p.id);
    if (p.kind == PointerDeviceKind.stylus ||
        p.kind == PointerDeviceKind.invertedStylus) {
      _penDown = false;
      _penSeen = p.time;
    }
    if (wasIgnored) return;
    _touches.remove(p.id);
    final wasPinch = _pinchIds.remove(p.id);
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
        if (!wasPinch) break; // a bystander lifted: nothing changes
        if (_pinchIds.length == 1 && _touches.containsKey(_pinchIds.single)) {
          // One of the pair left: carry on panning with the other, no fling.
          final id = _pinchIds.single;
          _pinchIds.clear();
          _mode = _Mode.pan;
          _lead = id;
          _last = _touches[id]!;
          _velocity.reset();
        } else {
          _pinchIds.clear();
          _finish(Offset.zero);
        }
      case _Mode.idle:
        break;
    }
  }

  void cancel(PointerSample p) {
    stats?.record('cancel', p);
    _ignored.remove(p.id);
    _forget(p.id);
    if (p.kind == PointerDeviceKind.stylus) _penDown = false;
    _touches.remove(p.id);
    if (_mode == _Mode.pinch && _pinchIds.contains(p.id)) {
      _pinchIds.remove(p.id);
      if (_pinchIds.length == 1 && _touches.containsKey(_pinchIds.single)) {
        final id = _pinchIds.single;
        _pinchIds.clear();
        _mode = _Mode.pan;
        _lead = id;
        _last = _touches[id]!;
        _velocity.reset();
      } else {
        _pinchIds.clear();
        _finish(Offset.zero);
      }
      return;
    }
    if (_mode == _Mode.tool && p.id == _lead) {
      _endTool(cancel: true);
    } else if ((_mode == _Mode.pan || _mode == _Mode.cardDrag) &&
        p.id == _lead) {
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

  /// Starts a pinch with [ids] (default: the first two touches). The ids in
  /// [fromTrail] count from where they were a moment ago, so the movement
  /// that started the gesture is not lost.
  void _beginPinch([List<int>? ids, Set<int> fromTrail = const {}]) {
    _mode = _Mode.pinch;
    _pinchIds
      ..clear()
      ..addAll(ids ?? _touches.keys.take(2));
    final pts = [
      for (final id in _pinchIds)
        fromTrail.contains(id) && (_trail[id]?.length ?? 0) >= 2
            ? _trailStart(id)
            : _touches[id]!,
    ];
    _pinchCentroid = (pts[0] + pts[1]) / 2;
    final d = (pts[0] - pts[1]).distance;
    _pinchDistance = d == 0 ? 1 : d;
    sink.gestureStart();
    if (fromTrail.isNotEmpty) _applyPinch();
  }

  void _applyPinch() {
    final (c, d) = _pinchMetrics();
    final factor = _pinchDistance == 0 ? 1.0 : d / _pinchDistance;
    sink.zoomPan(anchor: c, factor: factor, pan: c - _pinchCentroid);
    _pinchCentroid = c;
    _pinchDistance = d == 0 ? 1 : d;
  }

  (Offset, double) _pinchMetrics() {
    final pts = [for (final id in _pinchIds) _touches[id]!];
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
