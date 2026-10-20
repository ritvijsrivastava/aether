import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:meta/meta.dart';

/// Pan and zoom of the canvas: `screen = world * zoom + (x, y)`.
@immutable
class ViewState {
  const ViewState({this.x = 0, this.y = 0, this.zoom = 1});

  static const double minZoom = 0.2;
  static const double maxZoom = 3.0;

  final double x, y, zoom;

  Offset screenToWorld(Offset s) =>
      Offset((s.dx - x) / zoom, (s.dy - y) / zoom);

  Offset worldToScreen(Offset w) => Offset(w.dx * zoom + x, w.dy * zoom + y);

  /// The part of the world visible in a viewport of [viewport] size.
  Rect worldRect(Size viewport) => Rect.fromLTWH(
    -x / zoom,
    -y / zoom,
    viewport.width / zoom,
    viewport.height / zoom,
  );

  ViewState panBy(Offset screenDelta) =>
      ViewState(x: x + screenDelta.dx, y: y + screenDelta.dy, zoom: zoom);

  /// Zooms by [factor] keeping the world point under [anchor] fixed.
  ViewState zoomAt(Offset anchor, double factor) {
    final z = (zoom * factor).clamp(minZoom, maxZoom);
    final wx = (anchor.dx - x) / zoom, wy = (anchor.dy - y) / zoom;
    return ViewState(x: anchor.dx - wx * z, y: anchor.dy - wy * z, zoom: z);
  }

  /// Sets [zoom] absolutely, keeping the world point under [anchor] fixed.
  ViewState withZoomAt(Offset anchor, double newZoom) =>
      zoomAt(anchor, newZoom / zoom);

  /// A view that shows [target] (world rect) centred in the area of the
  /// viewport left after [insets], at the largest zoom that fits (capped at
  /// [maxFit]).
  static ViewState fitRect(
    Rect target,
    Size viewport, {
    EdgeInsets insets = EdgeInsets.zero,
    double padding = 32,
    double maxFit = 1.0,
  }) {
    final availW = math.max(
      1.0,
      viewport.width - insets.horizontal - padding * 2,
    );
    final availH = math.max(
      1.0,
      viewport.height - insets.vertical - padding * 2,
    );
    final z = math
        .min(availW / target.width, availH / target.height)
        .clamp(minZoom, maxFit);
    final cx = insets.left + (viewport.width - insets.horizontal) / 2;
    final cy = insets.top + (viewport.height - insets.vertical) / 2;
    return ViewState(
      x: cx - target.center.dx * z,
      y: cy - target.center.dy * z,
      zoom: z,
    );
  }

  static ViewState lerp(ViewState a, ViewState b, double t) => ViewState(
    x: lerpDouble(a.x, b.x, t)!,
    y: lerpDouble(a.y, b.y, t)!,
    // Interpolate zoom geometrically so zooming feels even.
    zoom: math.exp(lerpDouble(math.log(a.zoom), math.log(b.zoom), t)!),
  );

  @override
  bool operator ==(Object other) =>
      other is ViewState && other.x == x && other.y == y && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);

  @override
  String toString() => 'ViewState(x: $x, y: $y, zoom: $zoom)';
}
