import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../../../core/geometry/box.dart';
import '../../../domain/marks/spatial_grid.dart';
import '../../../domain/ink/ink_geometry.dart';
import '../../../domain/model/models.dart';
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

class _Strokes {
  final List<Ink> inks = [];

  /// A recorded picture of the first [baseCount] strokes; strokes added since
  /// are drawn on top one by one, until there are enough to be worth folding
  /// into a new picture. Erasing or undoing drops the picture.
  Picture? base;
  int baseCount = 0;
  Box? bounds;

  /// For a crowded page, the base picture drawn into a bitmap: replaying
  /// thousands of paths every frame costs the GPU far more than drawing one
  /// image. [bitmapScale] is pixels per page point; [bitmapBox] is the part of
  /// the page space the image covers.
  Image? bitmap;
  double bitmapScale = 0;
  Box? bitmapBox;
  int bitmapCount = 0;
  bool rendering = false;
  Timer? timer;

  void dropBitmap() {
    bitmap?.dispose();
    bitmap = null;
    bitmapScale = 0;
    bitmapBox = null;
    bitmapCount = 0;
    timer?.cancel();
    timer = null;
  }

  void dropBase() {
    base?.dispose();
    base = null;
    baseCount = 0;
    dropBitmap();
  }
}

/// The committed ink of the open board, all in world space.
///
/// The ink keeps a recorded [Picture], so panning and zooming replay one
/// display list instead of rebuilding thousands of paths. Adding a stroke draws
/// it on top of the picture; only after [foldAfter] such strokes is the
/// picture rebuilt.
class InkLayer extends ChangeNotifier {
  InkLayer({this.curve = PressureCurve.soft});

  /// Width of pressure, applied when drawing (so it can change later).
  PressureCurve curve;

  static const int foldAfter = 24;

  /// A page with more strokes than this is drawn from a bitmap while panning
  /// and zooming (measured: 10,000 strokes cost the S9's GPU 47 ms a frame as
  /// paths, which is 20 fps).
  static const int bitmapThreshold = 400;

  /// The longest side of a page bitmap, in pixels.
  static const int maxBitmapSide = 4096;

  /// How many page bitmaps have been drawn; for tests and the HUD.
  int bitmapRenders = 0;
  final _Strokes _s = _Strokes();
  final Map<String, Ink> _byId = {};
  final SpatialGrid _grid = SpatialGrid();

  /// Strokes a circle of radius [r] at ([x], [y]) touches.
  List<Ink> touching(double x, double y, double r) => [
    for (final id in _grid.query(Box(x - r, y - r, x + r, y + r)))
      if (InkGeometry.touches(_byId[id]!.samples, _byId[id]!.width, x, y, r))
        _byId[id]!,
  ];

  /// How many page pictures have been (re)recorded; for tests and the HUD.
  int rebuilds = 0;

  int get count => _byId.length;
  Iterable<Ink> get all => _byId.values;
  Ink? byId(String id) => _byId[id];

  /// Where the ink reaches, or null when there is none.
  Box? get bounds => _s.bounds;

  void replaceAll(Iterable<Ink> inks) {
    _s.dropBase();
    _s.inks.clear();
    _s.bounds = null;
    _byId.clear();
    _grid.clear();
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
    _grid.remove(id);
    _s.inks.removeWhere((i) => i.id == id);
    _s.dropBase();
    _s.bounds = _union(_s.inks);
    notifyListeners();
  }

  void _insert(Ink ink) {
    final old = _byId[ink.id];
    if (old != null) {
      _s.inks.removeWhere((i) => i.id == ink.id);
      _s.dropBase();
      _grid.remove(old.id);
    }
    _byId[ink.id] = ink;
    _grid.put(ink.id, ink.bounds);
    _s.inks.add(ink);
    _s.bounds = old == null && _s.bounds != null
        ? _s.bounds!.union(ink.bounds)
        : _union(_s.inks);
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

  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.medium;

  /// Paints the ink. [canvas] is in world space. [scale] is the screen pixels
  /// per world unit (zoom times pixel ratio), which decides how sharp a
  /// crowded board's bitmap needs to be.
  void paint(Canvas canvas, {double scale = 1}) {
    final page = _s;
    if (page.inks.isEmpty) return;
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
    if (page.baseCount > bitmapThreshold && _drawBitmap(canvas, page, scale)) {
      // The base is the image; strokes added since still go on top as paths.
    } else {
      canvas.drawPicture(page.base!);
    }
    for (var i = page.baseCount; i < page.inks.length; i++) {
      _drawInk(canvas, page.inks[i]);
    }
  }

  /// Draws the page's bitmap if it is sharp enough for [scale]; otherwise asks
  /// for a better one and returns false (the caller draws the paths).
  bool _drawBitmap(Canvas canvas, _Strokes page, double scale) {
    final box = page.bounds!;
    final side = math.max(box.width + 4, box.height + 4);
    final cap = maxBitmapSide / side; // the sharpest a bitmap can be
    final want = math.min(scale, cap);
    final img = page.bitmap;
    final usable =
        img != null &&
        page.bitmapCount == page.baseCount &&
        page.bitmapScale >= want * 0.6 &&
        // Zoomed in beyond what a bitmap can hold: paths are sharper.
        scale <= cap * 1.5;
    if (usable) {
      final b = page.bitmapBox!;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1),
        _imagePaint,
      );
      return true;
    }
    if (scale <= cap * 1.5) _scheduleBitmap(page, want);
    return false;
  }

  void _scheduleBitmap(_Strokes page, double want) {
    if (page.rendering || page.timer != null) return;
    // Wait for a zoom gesture to settle before spending a render on it.
    page.timer = Timer(const Duration(milliseconds: 120), () {
      page.timer = null;
      unawaited(_renderBitmap(page, want));
    });
  }

  Future<void> _renderBitmap(_Strokes page, double want) async {
    final base = page.base;
    final bounds = page.bounds;
    if (base == null || bounds == null || page.rendering) return;
    page.rendering = true;
    final count = page.baseCount;
    try {
      final box = Box(
        bounds.x0 - 2,
        bounds.y0 - 2,
        bounds.x1 + 2,
        bounds.y1 + 2,
      );
      // A little sharper than asked, so a small zoom-in does not need a redo.
      final side = math.max(box.width, box.height);
      final scale = math.min(want * 1.25, maxBitmapSide / side);
      final w = math.max(1, (box.width * scale).ceil());
      final h = math.max(1, (box.height * scale).ceil());
      final rec = PictureRecorder();
      Canvas(rec)
        ..scale(scale)
        ..translate(-box.x0, -box.y0)
        ..drawPicture(base);
      final pic = rec.endRecording();
      final img = await pic.toImage(w, h);
      pic.dispose();
      // The page may have changed while the image was being made.
      if (identical(page.base, base) && page.baseCount == count) {
        page.bitmap?.dispose();
        page.bitmap = img;
        page.bitmapScale = scale;
        page.bitmapBox = box;
        page.bitmapCount = count;
        bitmapRenders++;
        notifyListeners();
      } else {
        img.dispose();
      }
    } finally {
      page.rendering = false;
    }
  }

  @override
  void dispose() {
    _s.dropBase();
    super.dispose();
  }
}

/// Draws committed ink.
class InkPainter extends CustomPainter {
  InkPainter({required this.view, required this.ink, this.devicePixelRatio = 1})
    : super(repaint: Listenable.merge([view, ink]));

  final ValueListenable<ViewState> view;
  final InkLayer ink;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final b = ink.bounds;
    if (b == null) return;
    final v = view.value;
    if (!Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1).overlaps(v.worldRect(size))) {
      return;
    }
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    ink.paint(canvas, scale: v.zoom * devicePixelRatio);
    canvas.restore();
  }

  @override
  bool shouldRepaint(InkPainter old) =>
      old.view != view ||
      old.ink != ink ||
      old.devicePixelRatio != devicePixelRatio;
}

/// The stroke being drawn right now, and how stale its newest sample is when
/// a frame is painted (a measure of input-to-pixel delay, minus raster).
class LiveInk extends ChangeNotifier {
  Float32List _buf = Float32List(3 * 256);
  int _n = 0;
  final List<double> _recent = []; // x, y, ms triplets, last 4
  List<double> predicted = const [];

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

  void begin(double w, int argb) {
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
    required this.live,
    this.curve = PressureCurve.soft,
  }) : super(repaint: Listenable.merge([view, live]));

  final ValueListenable<ViewState> view;
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
      old.view != view || old.live != live;
}
