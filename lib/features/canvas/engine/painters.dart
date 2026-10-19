import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;
import 'package:flutter/painting.dart'
    show TextDirection, TextPainter, TextSpan, TextStyle, FontWeight;

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/dot_grid.dart';
import 'page_surface.dart';
import 'scene.dart';
import 'view_state.dart';

/// Where a card's drag handle sits on screen. One definition, used both to
/// paint the handle and to hit-test it, so they can never disagree.
///
/// The handle keeps a constant screen size whatever the zoom, so it is
/// always reachable, and is hidden once the card is too small to need it.
abstract final class HandleLayout {
  static const double height = 36;
  static const double hitHeight = 48;
  static const double gap = 10;
  static const double minCardWidth = 90;

  static final Map<String, double> _widths = {};

  static String label(Card card) => 'p. ${card.index + 1}';

  static double _textWidth(String text, TextStyle style) =>
      _widths.putIfAbsent(text, () {
        final p = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        if (_widths.length > 2000) _widths.remove(_widths.keys.first);
        return p.width;
      });

  static TextStyle style(Color color) => TextStyle(
    fontFamily: 'Figtree',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: color,
  );

  /// The visible handle, or null when the card is too small on screen.
  static Rect? rect(Card card, ViewState v, Color textColor) {
    if (card.rect.width * v.zoom < minCardWidth) return null;
    final w = 14 + 12 + 8 + _textWidth(label(card), style(textColor)) + 14;
    final left = card.rect.left * v.zoom + v.x;
    final bottom = card.rect.top * v.zoom + v.y - gap;
    return Rect.fromLTWH(left, bottom - height, w, height);
  }

  /// The tappable area: the handle, grown to a 48 dp target.
  static Rect? hitRect(Card card, ViewState v) {
    final r = rect(card, v, const Color(0xFF000000));
    return r?.inflate((hitHeight - height) / 2);
  }
}

/// The dot grid, repainting from the view so it pans and scales with it.
class GridPainter extends CustomPainter {
  GridPainter({required this.view, required this.color}) : super(repaint: view);

  final ValueListenable<ViewState> view;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final v = view.value;
    DotGridPainter(
      color: color,
      offset: Offset(v.x, v.y),
      zoom: v.zoom,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(GridPainter old) => old.color != color || old.view != view;
}

/// The paper cards and their content.
class CardsPainter extends CustomPainter {
  CardsPainter({
    required this.view,
    required this.scene,
    required this.surface,
    required this.tokens,
  }) : super(repaint: Listenable.merge([view, scene]));

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final PageSurface surface;
  final AetherTokens tokens;

  final Paint _paper = Paint();
  final Paint _shadowNear = Paint();
  final Paint _shadowFar = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final v = view.value;
    final visible = scene.value.visible(v.worldRect(size));
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    final soft = v.zoom >= 0.35;
    _paper.color = tokens.paper;
    final shadows = tokens.paperShadow;
    _shadowNear
      ..color = shadows[0].color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadows[0].blurSigma);
    _shadowFar
      ..color = shadows[1].color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadows[1].blurSigma);
    for (final c in visible) {
      final rr = RRect.fromRectAndRadius(
        c.rect,
        const Radius.circular(AetherTokens.rPaper),
      );
      if (soft) {
        canvas.drawRRect(rr.shift(shadows[1].offset), _shadowFar);
        canvas.drawRRect(rr.shift(shadows[0].offset), _shadowNear);
      } else {
        // Far out the blur is invisible and expensive: a flat edge will do.
        canvas.drawRRect(rr.shift(const Offset(0, 3)), _shadowNear);
      }
      canvas.drawRRect(rr, _paper);
      canvas.save();
      canvas.clipRRect(rr);
      surface.paint(canvas, c, v.zoom);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CardsPainter old) =>
      old.tokens != tokens ||
      old.surface != surface ||
      old.view != view ||
      old.scene != scene;
}

/// Drag handles in screen space, so they keep a constant size.
class HandlesPainter extends CustomPainter {
  HandlesPainter({
    required this.view,
    required this.scene,
    required this.tokens,
  }) : super(repaint: Listenable.merge([view, scene]));

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final AetherTokens tokens;

  final Paint _fill = Paint();
  final Paint _shadow = Paint();
  final Map<String, TextPainter> _labels = {};

  @override
  void paint(Canvas canvas, Size size) {
    final v = view.value;
    _fill.color = tokens.panel;
    final sh = tokens.handle.first;
    _shadow
      ..color = sh.color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sh.blurSigma);
    final style = HandleLayout.style(tokens.ink);
    for (final c in scene.value.visible(v.worldRect(size))) {
      final r = HandleLayout.rect(c, v, tokens.ink);
      if (r == null || r.bottom < 0 || r.top > size.height) continue;
      final rr = RRect.fromRectAndRadius(
        r,
        const Radius.circular(AetherTokens.rPill),
      );
      canvas.drawRRect(rr.shift(sh.offset), _shadow);
      canvas.drawRRect(rr, _fill);
      // Grip: six dots.
      final dot = Paint()..color = tokens.inkMuted;
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 2; col++) {
          canvas.drawCircle(
            Offset(r.left + 14 + col * 6, r.center.dy - 5.5 + row * 5.5),
            1.4,
            dot,
          );
        }
      }
      final label = HandleLayout.label(c);
      final tp = _labels.putIfAbsent(label, () {
        if (_labels.length > 500) _labels.remove(_labels.keys.first);
        return TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
      });
      tp.paint(
        canvas,
        Offset(r.left + 14 + 12 + 8, r.center.dy - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(HandlesPainter old) =>
      old.tokens != tokens || old.view != view || old.scene != scene;
}
