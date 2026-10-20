import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A colour swatch: a disc of [color] with a hairline edge (so pale colours
/// still read against the panel) and an ink ring when [selected].
class ColorDisc extends StatelessWidget {
  const ColorDisc(
    this.color, {
    super.key,
    this.size = 28,
    this.selected = false,
    this.semanticLabel,
  });

  final int color;
  final double size;
  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size + 8),
          painter: _DiscPainter(color, size, selected, t.ink, t.hairline),
        ),
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  _DiscPainter(this.color, this.d, this.selected, this.ring, this.edge);
  final int color;
  final double d;
  final bool selected;
  final Color ring, edge;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = d / 2;
    canvas.drawCircle(c, r, Paint()..color = Color(color));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );
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
  }

  @override
  bool shouldRepaint(_DiscPainter o) =>
      o.color != color ||
      o.d != d ||
      o.selected != selected ||
      o.ring != ring ||
      o.edge != edge;
}
