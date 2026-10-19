import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

import '../../../core/geometry/box.dart';
import '../../../domain/marks/highlight_index.dart';
import '../../../domain/model/models.dart';
import '../../../domain/text/text_selection.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/meaning_disc.dart' show meaningColor;
import '../engine/page_surface.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';

/// How highlights are drawn (DESIGN.md "Highlights"): the meaning colour at
/// half strength, multiplied into the page so the text underneath stays dark.
/// Bars are `rHighlight` (5 px on screen) rounded, whatever the zoom.
abstract final class HighlightPaint {
  static const double alpha = 0.5;
  static const double liveAlpha = 0.62;

  /// Paints [rects] (page space) at [origin] (the card's top-left, world
  /// space) into a canvas already in world space.
  static void paint(
    Canvas canvas,
    List<Box> rects,
    Offset origin,
    Meaning meaning,
    double zoom,
    Paint paint, {
    bool region = false,
  }) {
    final color = meaningColor(meaning);
    final radius = AetherTokens.rHighlight / zoom;
    paint
      ..blendMode = BlendMode.multiply
      ..style = PaintingStyle.fill;
    for (final r in rects) {
      final rr = RRect.fromLTRBR(
        r.x0 + origin.dx,
        r.y0 + origin.dy,
        r.x1 + origin.dx,
        r.y1 + origin.dy,
        Radius.circular(math.min(radius, r.height / 2)),
      );
      canvas.drawRRect(rr, paint);
      if (region) {
        // A rectangle over a figure has no text to show where it is, so it
        // keeps a thin edge in its own colour.
        canvas.drawRRect(
          rr,
          Paint()
            ..color = color.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / zoom,
        );
      }
    }
  }
}

/// The highlights of the open document, by page, and their painting.
///
/// Edits made through [add], [remove] and [replaceAll] notify listeners; the
/// cards painter repaints from this, so a new highlight appears on the next
/// frame without rebuilding any widget.
class HighlightLayer extends ChangeNotifier {
  final Map<String, List<Highlight>> _byPage = {};
  final Map<String, Highlight> _byId = {};
  final HighlightIndex _index = HighlightIndex();

  /// The highlight under page point ([x], [y]) at [zoom], within a fingertip's
  /// reach and at least 16 screen px tall, or null.
  Highlight? hitTest(String pageId, double x, double y, double zoom) =>
      _index.hitTest(pageId, x, y, zoom);

  /// Highlights a circle of radius [r] at page point ([x], [y]) touches.
  List<Highlight> touching(String pageId, double x, double y, double r) =>
      _index.touching(pageId, x, y, r);

  /// All highlights, in no particular order.
  Iterable<Highlight> get all => _byId.values;
  int get count => _byId.length;

  Highlight? byId(String id) => _byId[id];

  List<Highlight> forPage(String pageId) => _byPage[pageId] ?? const [];

  void replaceAll(Iterable<Highlight> highlights) {
    _byPage.clear();
    _byId.clear();
    _index.clear();
    for (final h in highlights) {
      _insert(h);
    }
    notifyListeners();
  }

  void add(Highlight h) {
    _insert(h);
    notifyListeners();
  }

  void remove(String id) {
    final h = _byId.remove(id);
    if (h == null) return;
    _index.remove(id);
    _byPage[h.pageId]?.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  void _insert(Highlight h) {
    final old = _byId[h.id];
    if (old != null) _byPage[old.pageId]?.removeWhere((x) => x.id == h.id);
    _byId[h.id] = h;
    _index.put(h);
    if (h.pageId != null) (_byPage[h.pageId!] ??= []).add(h);
  }

  final Paint _paint = Paint();

  /// Paints this page's highlights; [canvas] is in world space.
  void paintPage(Canvas canvas, Card card, PageViewInfo info) {
    final list = _byPage[card.id];
    if (list == null || list.isEmpty) return;
    for (final h in list) {
      _paint.color = meaningColor(h.meaning)
          .withValues(alpha: HighlightPaint.alpha);
      HighlightPaint.paint(
        canvas,
        h.rects,
        card.rect.topLeft,
        h.meaning,
        info.zoom,
        _paint,
        region: h.startChar < 0,
      );
    }
  }
}

/// The highlight being dragged out right now.
@immutable
class LiveMark {
  const LiveMark(this.cardId, this.selection, this.meaning);
  final String cardId;
  final MarkSelection selection;
  final Meaning meaning;
}

/// Draws the in-progress highlight in its own layer, so a drag repaints this
/// and nothing else.
class LiveMarkPainter extends CustomPainter {
  LiveMarkPainter({required this.view, required this.scene, required this.live})
    : super(repaint: Listenable.merge([view, scene, live]));

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final ValueListenable<LiveMark?> live;

  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final l = live.value;
    if (l == null) return;
    final card = scene.value.byId(l.cardId);
    if (card == null) return;
    final v = view.value;
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    canvas.clipRect(card.rect);
    _paint.color = meaningColor(l.meaning)
        .withValues(alpha: HighlightPaint.liveAlpha);
    HighlightPaint.paint(
      canvas,
      l.selection.rects,
      card.rect.topLeft,
      l.meaning,
      v.zoom,
      _paint,
      region: l.selection.isRegion,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveMarkPainter old) =>
      old.view != view || old.scene != scene || old.live != live;
}
