import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

import '../../../core/geometry/box.dart';
import '../../../domain/model/models.dart';
import '../../../ui/theme/tokens.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';

/// A highlight being pointed at after a jump from Extract.
@immutable
class Flash {
  const Flash(this.cardId, this.rects, this.meaning);
  final String cardId;
  final List<Box> rects;
  final Meaning meaning;
}

/// Shows one [Flash] for about a second and then clears it.
///
/// With "remove animations" on, the outline stays at full strength for the
/// same time instead of fading, so the jump is still easy to follow.
class FlashController {
  FlashController(TickerProvider vsync)
    : _anim = AnimationController(vsync: vsync, duration: duration) {
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) current.value = null;
    });
  }

  static const Duration duration = Duration(milliseconds: 1400);

  final AnimationController _anim;
  final ValueNotifier<Flash?> current = ValueNotifier(null);
  bool reduceMotion = false;

  Animation<double> get progress => _anim;

  void show(Flash flash) {
    current.value = flash;
    _anim.forward(from: 0);
  }

  void dispose() {
    _anim.dispose();
    current.dispose();
  }
}

/// Draws the flash: an ink outline around the highlight that fades out.
class FlashPainter extends CustomPainter {
  FlashPainter({
    required this.view,
    required this.scene,
    required this.flash,
    required this.tokens,
  }) : super(
         repaint: Listenable.merge([
           view,
           scene,
           flash.current,
           flash.progress,
         ]),
       );

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final FlashController flash;
  final AetherTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final f = flash.current.value;
    if (f == null) return;
    final card = scene.value.byId(f.cardId);
    if (card == null) return;
    final v = view.value;
    final t = flash.progress.value;
    // Hold, then ease out: strong for the first third, then gone.
    final fade = flash.reduceMotion
        ? 1.0
        : 1 - Curves.easeOut.transform(((t - 0.3) / 0.7).clamp(0.0, 1.0));
    if (fade <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 / v.zoom
      ..color = tokens.ink.withValues(alpha: 0.85 * fade);
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    final grow = 3 / v.zoom;
    final radius = Radius.circular(AetherTokens.rHighlight / v.zoom + grow);
    for (final r in f.rects) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          r.x0 + card.rect.left - grow,
          r.y0 + card.rect.top - grow,
          r.x1 + card.rect.left + grow,
          r.y1 + card.rect.top + grow,
          radius,
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FlashPainter old) =>
      old.view != view ||
      old.scene != scene ||
      old.flash != flash ||
      old.tokens != tokens;
}
