import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

/// Stroke icons on a 24-unit grid (2 px round stroke), the same set the
/// prototype uses, drawn from SVG path data so no icon font is needed.
abstract final class AetherIcons {
  static const link =
      'M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71';
  static const lasso =
      'M7 22a5 5 0 0 1-2-4M3.3 14A6.8 6.8 0 0 1 2 10c0-4.4 4.5-8 10-8s10 3.6 10 8-4.5 8-10 8a12 12 0 0 1-5-1M5 18a2 2 0 1 0 0-4 2 2 0 0 0 0 4z';
  static const pan =
      'M5 9l-3 3 3 3M9 5l3-3 3 3M15 19l-3 3-3-3M19 9l3 3-3 3M2 12h20M12 2v20';
  static const mark =
      'm9 11-6 6v3h9l3-3M22 12l-4.6 4.6a2 2 0 0 1-2.8 0l-5.2-5.2a2 2 0 0 1 0-2.8L14 4';
  static const pen = 'M12 20h9M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z';
  static const eraser =
      'm7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21M22 21H7M5 11l9 9';
  static const note =
      'M16 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V8ZM15 3v6h6';
  static const undo = 'M3 7v6h6M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13';
  static const redo = 'M21 7v6h-6M3 17a9 9 0 0 1 9-9 9 9 0 0 1 6 2.3L21 13';
  static const list = 'M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01';
  static const more = 'M12 12h.01M19 12h.01M5 12h.01';
  static const plus = 'M12 5v14M5 12h14';
  static const minus = 'M5 12h14';
  static const settings =
      'M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6';
  static const back = 'm15 18-6-6 6-6';
  static const doc =
      'M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2zM14 2v6h6';
  static const trash =
      'M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6M10 11v6M14 11v6';
  static const paste =
      'M9 2h6a1 1 0 0 1 1 1v2a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1ZM9 4H6a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-3';
  static const copy =
      'M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2ZM4 16a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2';
  static const palette =
      'M12 22a1 1 0 0 1 0-20 10 9 0 0 1 10 9 5 5 0 0 1-5 5h-2.25a1.75 1.75 0 0 0-1.4 2.8l.3.4A1.75 1.75 0 0 1 12 22zM13.5 6.5h.01M17.5 10.5h.01M6.5 12.5h.01M8.5 7.5h.01';
  static const fit =
      'M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M16 21h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3';
  static const upload =
      'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12';
}

final Map<String, Path> _parsed = {};
Path _path(String d) => _parsed.putIfAbsent(d, () => parseSvgPathData(d));

/// Draws one of [AetherIcons] at [size] with [color].
class AetherIcon extends StatelessWidget {
  const AetherIcon(
    this.path, {
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth = 2,
  });

  final String path;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color!;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _IconPainter(path, c, strokeWidth),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.d, this.color, this.strokeWidth);
  final String d;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    canvas.drawPath(
      _path(d),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_IconPainter o) =>
      o.d != d || o.color != color || o.strokeWidth != strokeWidth;
}
