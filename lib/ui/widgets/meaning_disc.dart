import 'package:flutter/material.dart';

import '../../domain/model/models.dart';
import '../theme/tokens.dart';

Color meaningColor(Meaning m) => switch (m) {
  Meaning.claim => AetherTokens.claim,
  Meaning.method => AetherTokens.method,
  Meaning.question => AetherTokens.question,
};

/// A meaning swatch: a coloured disc with its glyph (circle, diamond,
/// triangle) in ink. The glyph, not the colour, carries the meaning, because
/// the colours alone fail 3:1 against the panel.
class MeaningDisc extends StatelessWidget {
  const MeaningDisc(
    this.meaning, {
    super.key,
    this.size = 28,
    this.selected = false,
    this.semanticLabel,
  });

  final Meaning meaning;
  final double size;
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: semanticLabel ?? meaning.label,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size + 8),
          painter: _DiscPainter(meaning, size, selected, t.ink),
        ),
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  _DiscPainter(this.meaning, this.d, this.selected, this.ring);
  final Meaning meaning;
  final double d;
  final bool selected;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = d / 2;
    canvas.drawCircle(c, r, Paint()..color = meaningColor(meaning));
    if (selected) {
      canvas.drawCircle(
        c,
        r + 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ring,
      );
    }
    final g = Paint()..color = AetherTokens.onMark;
    final k = r * .46;
    switch (meaning) {
      case Meaning.claim:
        canvas.drawCircle(c, k * .8, g);
      case Meaning.method:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - k)
            ..lineTo(c.dx + k, c.dy)
            ..lineTo(c.dx, c.dy + k)
            ..lineTo(c.dx - k, c.dy)
            ..close(),
          g,
        );
      case Meaning.question:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - k)
            ..lineTo(c.dx + k * 1.05, c.dy + k * .8)
            ..lineTo(c.dx - k * 1.05, c.dy + k * .8)
            ..close(),
          g,
        );
    }
  }

  @override
  bool shouldRepaint(_DiscPainter o) =>
      o.meaning != meaning ||
      o.d != d ||
      o.selected != selected ||
      o.ring != ring;
}
