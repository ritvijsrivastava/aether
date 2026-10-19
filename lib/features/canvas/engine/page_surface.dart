import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show Listenable, immutable;
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection, FontWeight;

import 'scene.dart';

/// What a surface needs to know about the view while painting a frame.
@immutable
class PageViewInfo {
  const PageViewInfo({
    required this.zoom,
    required this.viewportWorld,
    this.devicePixelRatio = 1,
  });

  /// Current view zoom (screen logical px per world unit).
  final double zoom;

  /// The visible part of the world.
  final Rect viewportWorld;
  final double devicePixelRatio;
}

/// Paints the content of each page into its card. The cards painter draws the
/// paper (shadow and white sheet); a surface draws what is on it.
///
/// A frame is `beginFrame`, then `paint` for every visible card, then
/// `endFrame`, so a surface can plan its work (which tiles to fetch, what to
/// evict) across all pages at once.
///
/// [PdfPageSurface] draws cached pdfium tiles; [SyntheticPageSurface] draws a
/// numbered placeholder so the engine can be judged without any PDF.
abstract interface class PageSurface {
  /// Fires when the surface has new content (a tile arrived); the cards
  /// painter repaints on it. Null for surfaces that never change by
  /// themselves.
  Listenable? get repaint;

  void beginFrame();

  /// [canvas] is already in world space; draw inside [card.rect].
  void paint(Canvas canvas, Card card, PageViewInfo info);

  void endFrame();

  /// A one-line status for the performance overlay, if any.
  String? get stats;
}

/// Numbered placeholder pages with line bars standing in for text.
class SyntheticPageSurface implements PageSurface {
  SyntheticPageSurface({
    this.numberColor = const Color(0x1F2B2723),
    this.barColor = const Color(0x142B2723),
  });

  final Color numberColor;
  final Color barColor;
  final Map<int, TextPainter> _numbers = {};
  final Paint _bar = Paint();

  @override
  Listenable? get repaint => null;

  @override
  String? get stats => null;

  @override
  void beginFrame() {}

  @override
  void endFrame() {}

  @override
  void paint(Canvas canvas, Card card, PageViewInfo info) {
    final r = card.rect;
    if (info.zoom >= 0.4) {
      _bar.color = barColor;
      final left = r.left + 56, width = r.width - 112;
      var row = 0;
      for (var y = r.top + 64; y < r.bottom - 56; y += 20, row++) {
        // Deterministic ragged right edge, so scrolling reads as text.
        final frac = 0.55 + 0.45 * ((card.index * 31 + row * 17) % 23) / 22;
        final isParaEnd = row % 9 == 8;
        final w = width * (isParaEnd ? frac * 0.5 : frac);
        if (row % 9 == 0 && row > 0) continue; // paragraph gap
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, y, w, 7),
            const Radius.circular(3),
          ),
          _bar,
        );
      }
    }
    final tp = _numbers.putIfAbsent(card.index, () {
      final p = TextPainter(
        text: TextSpan(
          text: '${card.index + 1}',
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 220,
            fontWeight: FontWeight.w700,
            color: numberColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (_numbers.length > 200) _numbers.remove(_numbers.keys.first);
      return p;
    });
    final s = math.min(1.0, (r.width * 0.8) / tp.width);
    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.scale(s);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}
