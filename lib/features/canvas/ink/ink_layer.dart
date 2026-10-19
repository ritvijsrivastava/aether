import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../../../core/geometry/box.dart';
import '../../../domain/marks/spatial_grid.dart';
import '../../../domain/ink/ink_geometry.dart';
import '../../../domain/model/models.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';
import '../input/pen_config.dart';

/// The outline of a stroke as a fillable path.
Path strokePath(
  Float32List samples,
  double width,
  PressureCurve curve, {
  double? constantWidth,
}) {
  final center = InkGeometry.centerline(
    samples,
    (p) => constantWidth ?? width * curve.apply(p),
  );
  final o = InkGeometry.outline(center);
  final path = Path();
  if (o.length < 6) return path;
  path.moveTo(o[0], o[1]);
  for (var i = 2; i < o.length; i += 2) {
    path.lineTo(o[i], o[i + 1]);
  }
  path.close();
  return path;
}

class _PageInk {
  final List<Ink> inks = [];

  /// A recorded picture of the first [baseCount] strokes; strokes added since
  /// are drawn on top one by one, until there are enough to be worth folding
  /// into a new picture. Erasing or undoing drops the picture.
  Picture? base;
  int baseCount = 0;
  Box? bounds;

  void dropBase() {
    base?.dispose();
    base = null;
    baseCount = 0;
  }
}

/// The committed ink of the open document: strokes by page (in page space) and
/// the strokes that belong to no page (in canvas space).
///
/// Each page keeps a recorded [Picture] of its ink, so panning and zooming
/// replay one display list per page instead of rebuilding thousands of paths
/// (SPEC 5.5). Adding a stroke draws it on top of the picture; only after
/// [foldAfter] such strokes is the picture rebuilt.
class InkLayer extends ChangeNotifier {
  InkLayer({this.curve = PressureCurve.soft});

  /// Width of pressure, applied when drawing (so it can change later).
  PressureCurve curve;

  static const int foldAfter = 24;
  static const String _free = '';

  final Map<String, _PageInk> _pages = {};
  final Map<String, Ink> _byId = {};
  final Map<String, SpatialGrid> _grids = {};

  /// Strokes a circle of radius [r] at ([x], [y]) touches, in the page's space
  /// (or canvas space for a null [pageId]).
  List<Ink> touching(String? pageId, double x, double y, double r) {
    final grid = _grids[pageId ?? _free];
    if (grid == null) return const [];
    return [
      for (final id in grid.query(Box(x - r, y - r, x + r, y + r)))
        if (InkGeometry.touches(_byId[id]!.samples, _byId[id]!.width, x, y, r))
          _byId[id]!,
    ];
  }

  /// How many page pictures have been (re)recorded; for tests and the HUD.
  int rebuilds = 0;

  int get count => _byId.length;
  Iterable<Ink> get all => _byId.values;
  Ink? byId(String id) => _byId[id];

  List<Ink> forPage(String? pageId) =>
      _pages[pageId ?? _free]?.inks ?? const [];

  /// Where this page's ink reaches, in page space (it may run past the page).
  Box? boundsOf(String? pageId) => _pages[pageId ?? _free]?.bounds;

  void replaceAll(Iterable<Ink> inks) {
    for (final p in _pages.values) {
      p.dropBase();
    }
    _pages.clear();
    _byId.clear();
    _grids.clear();
    for (final i in inks) {
      _insert(i);
    }
    notifyListeners();
  }

  void add(Ink ink) {
    _insert(ink);
    notifyListeners();
  }

  void remove(String id) {
    final ink = _byId.remove(id);
    if (ink == null) return;
    _grids[ink.pageId ?? _free]?.remove(id);
    final page = _pages[ink.pageId ?? _free];
    if (page != null) {
      page.inks.removeWhere((i) => i.id == id);
      page.dropBase();
      page.bounds = _union(page.inks);
      if (page.inks.isEmpty) _pages.remove(ink.pageId ?? _free);
    }
    notifyListeners();
  }

  void _insert(Ink ink) {
    final old = _byId[ink.id];
    if (old != null) {
      final p = _pages[old.pageId ?? _free];
      p?.inks.removeWhere((i) => i.id == ink.id);
      p?.dropBase();
      _grids[old.pageId ?? _free]?.remove(old.id);
    }
    _byId[ink.id] = ink;
    (_grids[ink.pageId ?? _free] ??= SpatialGrid()).put(ink.id, ink.bounds);
    final page = _pages[ink.pageId ?? _free] ??= _PageInk();
    page.inks.add(ink);
    final b = ink.bounds;
    page.bounds = page.bounds == null ? b : page.bounds!.union(b);
  }

  static Box? _union(List<Ink> inks) {
    Box? b;
    for (final i in inks) {
      b = b == null ? i.bounds : b.union(i.bounds);
    }
    return b;
  }

  final Paint _paint = Paint()..isAntiAlias = true;

  void _drawInk(Canvas canvas, Ink ink) {
    _paint.color = Color(ink.color);
    canvas.drawPath(strokePath(ink.samples, ink.width, curve), _paint);
  }

  /// Paints a page's ink. [canvas] is in that page's space (origin at the
  /// page's top-left), or in canvas space for [pageId] null.
  void paint(Canvas canvas, String? pageId) {
    final page = _pages[pageId ?? _free];
    if (page == null || page.inks.isEmpty) return;
    final extras = page.inks.length - page.baseCount;
    if (page.base == null || extras > foldAfter) {
      page.dropBase();
      final rec = PictureRecorder();
      final c = Canvas(rec);
      for (final i in page.inks) {
        _drawInk(c, i);
      }
      page.base = rec.endRecording();
      page.baseCount = page.inks.length;
      rebuilds++;
    }
    canvas.drawPicture(page.base!);
    for (var i = page.baseCount; i < page.inks.length; i++) {
      _drawInk(canvas, page.inks[i]);
    }
  }

  @override
  void dispose() {
    for (final p in _pages.values) {
      p.dropBase();
    }
    super.dispose();
  }
}

/// Draws committed ink above the pages.
class InkPainter extends CustomPainter {
  InkPainter({required this.view, required this.scene, required this.ink})
    : super(repaint: Listenable.merge([view, scene, ink]));

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final InkLayer ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (ink.count == 0) return;
    final v = view.value;
    final world = v.worldRect(size);
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    for (final card in scene.value.cards) {
      final b = ink.boundsOf(card.id);
      if (b == null) continue;
      // Ink may run past its page, so cull by the ink's own reach.
      final reach = Rect.fromLTRB(
        card.rect.left + b.x0,
        card.rect.top + b.y0,
        card.rect.left + b.x1,
        card.rect.top + b.y1,
      );
      if (!reach.overlaps(world)) continue;
      canvas.save();
      canvas.translate(card.rect.left, card.rect.top);
      ink.paint(canvas, card.id);
      canvas.restore();
    }
    final free = ink.boundsOf(null);
    if (free != null &&
        Rect.fromLTRB(free.x0, free.y0, free.x1, free.y1).overlaps(world)) {
      ink.paint(canvas, null);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(InkPainter old) =>
      old.view != view || old.scene != scene || old.ink != ink;
}

/// The stroke being drawn right now, and how stale its newest sample is when
/// a frame is painted (a measure of input-to-pixel delay, minus raster).
class LiveInk extends ChangeNotifier {
  Float32List _buf = Float32List(3 * 256);
  int _n = 0;
  final List<double> _recent = []; // x, y, ms triplets, last 4
  List<double> predicted = const [];

  String? cardId;
  double width = 2.5;
  int color = 0xFF2B2723;
  bool active = false;
  Duration lastSampleTime = Duration.zero;

  // How old the newest sample was at the start of each painted frame.
  int ageCount = 0;
  double ageSumMs = 0, ageMaxMs = 0;

  int get pointCount => _n;

  /// The samples so far (a view, not a copy: do not keep it).
  Float32List get samples => Float32List.sublistView(_buf, 0, _n * 3);

  void begin(String? card, double w, int argb) {
    cardId = card;
    width = w;
    color = argb;
    _n = 0;
    _recent.clear();
    predicted = const [];
    active = true;
    ageCount = 0;
    ageSumMs = 0;
    ageMaxMs = 0;
  }

  void add(
    double x,
    double y,
    double pressure,
    Duration time, {
    bool predict = false,
  }) {
    if (_n * 3 + 3 > _buf.length) {
      final bigger = Float32List(_buf.length * 2)..setAll(0, _buf);
      _buf = bigger;
    }
    _buf[_n * 3] = x;
    _buf[_n * 3 + 1] = y;
    _buf[_n * 3 + 2] = pressure;
    _n++;
    lastSampleTime = time;
    _recent
      ..add(x)
      ..add(y)
      ..add(time.inMicroseconds / 1000);
    if (_recent.length > 12) _recent.removeRange(0, 3);
    predicted = predict ? InkGeometry.predict(_recent) : const [];
    notifyListeners();
  }

  void end() {
    active = false;
    _n = 0;
    predicted = const [];
    notifyListeners();
  }

  void recordAge(Duration frame) {
    if (frame == Duration.zero || lastSampleTime == Duration.zero) return;
    final ms = (frame - lastSampleTime).inMicroseconds / 1000;
    if (ms < 0 || ms > 1000) return; // a different clock, or a stalled frame
    ageCount++;
    ageSumMs += ms;
    if (ms > ageMaxMs) ageMaxMs = ms;
  }

  String get stats => ageCount == 0
      ? 'ink: no stroke yet'
      : 'ink sample age avg ${(ageSumMs / ageCount).toStringAsFixed(1)} ms'
            ' · max ${ageMaxMs.toStringAsFixed(1)} ms';
}

/// Draws the stroke in progress, and the short stretch the pen is predicted to
/// cover next at half strength.
class LiveInkPainter extends CustomPainter {
  LiveInkPainter({
    required this.view,
    required this.scene,
    required this.live,
    this.curve = PressureCurve.soft,
  }) : super(repaint: Listenable.merge([view, scene, live]));

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final LiveInk live;
  final PressureCurve curve;

  final Paint _paint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (!live.active || live.pointCount == 0) return;
    live.recordAge(SchedulerBinding.instance.currentSystemFrameTimeStamp);
    final v = view.value;
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    if (live.cardId != null) {
      final card = scene.value.byId(live.cardId!);
      if (card == null) {
        canvas.restore();
        return;
      }
      canvas.translate(card.rect.left, card.rect.top);
    }
    final s = live.samples;
    _paint.color = Color(live.color);
    canvas.drawPath(strokePath(s, live.width, curve), _paint);
    final pr = live.predicted;
    if (pr.isNotEmpty) {
      final last = s.length - 3;
      final tail = Float32List.fromList([
        s[last],
        s[last + 1],
        s[last + 2],
        pr[0],
        pr[1],
        s[last + 2],
        pr[2],
        pr[3],
        s[last + 2],
      ]);
      _paint.color = Color(live.color).withValues(alpha: 0.5);
      canvas.drawPath(strokePath(tail, live.width, curve), _paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveInkPainter old) =>
      old.view != view || old.scene != scene || old.live != live;
}
