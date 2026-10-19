import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart' show CustomPainter;

/// Dot positions for one frame of the grid.
///
/// The grid scales with the view, but below [minStep] screen pixels apart the
/// dots turn to noise and the point count balloons, so the pitch doubles
/// until they are readable again. The result is bounded: a 2560x1600 view
/// never needs more than about 21 000 points, whatever the zoom (one
/// draw call and a 170 KB buffer at worst).
({Float32List points, int count, double step}) gridPoints(
  Size size, {
  required Offset offset,
  required double zoom,
  double pitch = 32,
  double minStep = 14,
}) {
  var step = pitch * zoom;
  while (step < minStep) {
    step *= 2;
  }
  final startX = offset.dx % step;
  final startY = offset.dy % step;
  final cols = ((size.width - startX) / step).ceil() + 1;
  final rows = ((size.height - startY) / step).ceil() + 1;
  final out = Float32List(cols * rows * 2);
  var n = 0;
  for (var r = 0; r < rows; r++) {
    final y = startY + r * step;
    if (y > size.height) break;
    for (var c = 0; c < cols; c++) {
      final x = startX + c * step;
      if (x > size.width) break;
      out[n++] = x;
      out[n++] = y;
    }
  }
  return (points: out, count: n ~/ 2, step: step);
}

/// The desk's dot grid: pans and scales with the view so the surface reads as
/// endless. Drawn as one call (round-capped points), not one per dot.
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
    final g = gridPoints(size, offset: offset, zoom: zoom, pitch: pitch);
    final diameter = (2.4 * zoom).clamp(1.8, 3.6);
    canvas.drawRawPoints(
      PointMode.points,
      Float32List.sublistView(g.points, 0, g.count * 2),
      Paint()
        ..color = color
        ..strokeWidth = diameter
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(DotGridPainter o) =>
      o.color != color ||
      o.offset != offset ||
      o.zoom != zoom ||
      o.pitch != pitch;
}
