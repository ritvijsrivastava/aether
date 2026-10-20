import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

import '../../../domain/ink/ink_geometry.dart';
import '../../../domain/model/models.dart';
import '../engine/view_state.dart';
import '../ink/ink_layer.dart';
import '../input/tool_gestures.dart';
import '../../../ui/theme/tokens.dart';

/// Where one finished erase goes: the marks it removed, and the pieces left
/// of strokes it only partly wiped. Both are one undo step.
abstract interface class EraseSink {
  String newId();
  void commitErase({required Set<String> deleted, required List<Ink> created});
}

/// The eraser ring under the pen while erasing.
class EraserState extends ChangeNotifier {
  Offset? center;
  double radiusPx = EraseToolController.radiusDp;

  void show(Offset screen) {
    center = screen;
    notifyListeners();
  }

  void hide() {
    center = null;
    notifyListeners();
  }
}

/// The Erase tool: wipe across strokes to remove them. By default a touched stroke goes whole; with partial erase on, only
/// the part under the eraser goes and the rest stays as separate strokes.
///
/// Marks vanish from the page as the eraser touches them, so the user sees
/// what is going. Nothing is written until the pen lifts, and then the whole
/// wipe is one undo step. Escape (cancel) puts everything back.
class EraseToolController implements ToolHandler {
  EraseToolController({
    required this.view,
    required this.ink,
    required this.eraser,
    required this.partial,
    this.radiusFn,
    this.sink,
  });

  /// The default eraser radius in screen dp (SPEC 5.7: 14 = 28 dp tip).
  static const double radiusDp = 14;

  final ValueListenable<ViewState> view;
  final InkLayer ink;
  final EraserState eraser;

  /// Partial erase on or off, read when the wipe starts.
  final bool Function() partial;

  /// The eraser's radius in screen dp, read when the wipe starts so a
  /// thickness change mid-wipe cannot tear the ring.
  double radiusNow() => radiusFn?.call() ?? radiusDp;
  final double Function()? radiusFn;

  EraseSink? sink;

  bool _active = false;
  bool _partial = false;
  Offset? _lastWorld;

  // What this wipe has taken from the page, kept so a cancel can put it back.
  final Map<String, Ink> _removed = {};
  final Map<String, Ink> _made = {}; // pieces created by partial erase

  bool get isActive => _active;

  /// Marks taken so far in this wipe (for tests and the overlay).
  int get removedCount => _removed.length;

  @override
  void start(ToolPoint p) {
    if (sink == null) return;
    _active = true;
    _partial = partial();
    eraser.radiusPx = radiusNow();
    _removed.clear();
    _made.clear();
    _lastWorld = null;
    eraser.show(p.position);
    _wipeTo(p.position);
  }

  @override
  void move(ToolPoint p) {
    if (!_active) return;
    eraser.show(p.position);
    _wipeTo(p.position);
  }

  @override
  void end(ToolPoint p) {
    if (!_active) return;
    _wipeTo(p.position);
    final deleted = _removed.keys.toSet();
    final created = _made.values.toList();
    _reset();
    if (deleted.isEmpty && created.isEmpty) return;
    sink?.commitErase(deleted: deleted, created: created);
  }

  @override
  void cancel() {
    if (!_active) return;
    for (final m in _made.keys) {
      ink.remove(m);
    }
    for (final m in _removed.values) {
      ink.add(m);
    }
    _reset();
  }

  void _reset() {
    _active = false;
    _lastWorld = null;
    _removed.clear();
    _made.clear();
    eraser.hide();
  }

  /// Wipes from the last position to [screen], in steps no longer than half the
  /// eraser's radius so a fast stroke cannot jump over a thin line.
  void _wipeTo(Offset screen) {
    final zoom = view.value.zoom;
    final to = view.value.screenToWorld(screen);
    final from = _lastWorld ?? to;
    _lastWorld = to;
    final r = radiusNow() / zoom;
    final dist = (to - from).distance;
    final steps = dist <= 0 ? 1 : (dist / (r / 2)).ceil();
    for (var i = 1; i <= steps; i++) {
      _eraseAt(Offset.lerp(from, to, i / steps)!, r);
    }
  }

  void _eraseAt(Offset w, double r) {
    for (final s in ink.touching(w.dx, w.dy, r)) {
      _eraseInk(s, w, r);
    }
  }

  void _eraseInk(Ink s, Offset at, double r) {
    final pieces = _partial
        ? InkGeometry.eraseSplit(s.samples, s.width, at.dx, at.dy, r)
        : const <Float32List>[];
    if (_partial && pieces.length == 1 && identical(pieces.first, s.samples)) {
      return; // the circle missed the centre line after all
    }
    ink.remove(s.id);
    if (_made.remove(s.id) == null) _removed[s.id] = s;
    for (final p in pieces) {
      final piece = Ink(
        id: sink!.newId(),
        docId: s.docId,
        samples: p,
        width: s.width,
        color: s.color,
      );
      ink.add(piece);
      _made[piece.id] = piece;
    }
  }
}

/// Draws the eraser ring at the pen.
class EraserPainter extends CustomPainter {
  EraserPainter({required this.eraser, required this.tokens})
    : super(repaint: eraser);

  final EraserState eraser;
  final AetherTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final c = eraser.center;
    if (c == null) return;
    canvas.drawCircle(
      c,
      eraser.radiusPx,
      Paint()..color = tokens.ink.withValues(alpha: 0.08),
    );
    canvas.drawCircle(
      c,
      eraser.radiusPx,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = tokens.ink.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(EraserPainter old) =>
      old.eraser != eraser || old.tokens != tokens;
}
