import 'package:flutter/material.dart';

/// The desk's dot grid. Pans and scales with the view so the surface reads as
/// endless. [pitch] is 32 canvas units.
class DotGridPainter extends CustomPainter {
  const DotGridPainter({
    required this.color,
    this.offset = Offset.zero,
    this.zoom = 1,
    this.pitch = 32,
  });

  final Color color;
  final Offset offset;
  final double zoom;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final step = pitch * zoom;
    if (step < 6) return; // too dense to read; skip instead of painting noise
    final p = Paint()..color = color;
    final r = (1.2 * zoom).clamp(.8, 2.0);
    final startX = offset.dx % step;
    final startY = offset.dy % step;
    for (var y = startY; y < size.height; y += step) {
      for (var x = startX; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(DotGridPainter o) =>
      o.color != color ||
      o.offset != offset ||
      o.zoom != zoom ||
      o.pitch != pitch;
}
