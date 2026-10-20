import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

import '../../../ui/widgets/dot_grid.dart';
import 'view_state.dart';

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
