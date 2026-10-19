import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

/// Edge of a square tile, in pixels.
const int tileSize = 512;

/// One tile of one page at one level of detail.
@immutable
class TileKey {
  const TileKey(this.page, this.lod, this.tx, this.ty);

  /// Zero-based page index.
  final int page;

  /// Level of detail; see [TileMath.scaleOf].
  final int lod;

  /// Tile column and row within the page at this level of detail.
  final int tx, ty;

  @override
  bool operator ==(Object other) =>
      other is TileKey &&
      other.page == page &&
      other.lod == lod &&
      other.tx == tx &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(page, lod, tx, ty);

  @override
  String toString() => 'Tile(p$page lod$lod $tx,$ty)';
}

/// Level-of-detail arithmetic.
///
/// A level of detail is an integer `n` meaning `sqrt(2)^n` pixels per page
/// point. Snapping the wanted scale to those steps (rather than rendering at
/// the exact zoom) keeps a pinch from invalidating every tile on every frame:
/// tiles stay valid across a ~41% zoom range.
abstract final class TileMath {
  static final double _lnRoot2 = math.log(math.sqrt2);

  /// Coarsest and finest levels: 1/16 and 8 pixels per point. The finest
  /// matches 300% zoom on a 2.6x display.
  static const int minLod = -8;
  static const int maxLod = 6;

  /// Largest page bitmap edge we are willing to describe, in pixels.
  static const double maxPagePixels = 16384;

  /// `sqrt(2)^lod`, computed as `2^(lod/2)` so even levels are exact powers
  /// of two (`pow(sqrt2, 4)` is 4.000000000000001, which would round a
  /// 612-point page up to 2449 pixels instead of 2448).
  static double scaleOf(int lod) => math.pow(2.0, lod / 2.0).toDouble();

  /// The level of detail to render a [page] at, for a screen scale of
  /// [screenScale] device pixels per page point (zoom times pixel ratio).
  ///
  /// Rounds up, so rendering is never softer than the screen needs, and backs
  /// off for oversized pages so a poster cannot ask for a gigapixel bitmap.
  static int lodFor(double screenScale, Size page) {
    final s = screenScale <= 0 ? scaleOf(minLod) : screenScale;
    var lod = (math.log(s) / _lnRoot2 - 1e-9).ceil().clamp(minLod, maxLod);
    while (lod > minLod &&
        (page.width * scaleOf(lod) > maxPagePixels ||
            page.height * scaleOf(lod) > maxPagePixels)) {
      lod--;
    }
    return lod;
  }

  /// The finest level at which the whole [page] fits in a single tile. It is
  /// always requested first, so there is something to show while sharper
  /// tiles render.
  static int baseLod(Size page) {
    final maxDim = math.max(page.width, page.height);
    if (maxDim <= 0) return minLod;
    return (math.log(tileSize / maxDim) / _lnRoot2).floor().clamp(
      minLod,
      maxLod,
    );
  }
}

/// Pixel and page-space layout of one page's tiles at one level of detail.
class TileGeometry {
  TileGeometry(this.page, this.lod) {
    final scale = TileMath.scaleOf(lod);
    // Whole pixels, so tiles line up exactly; the sub-pixel stretch this
    // introduces (under one pixel across the page) is invisible.
    fullWidth = math.max(1, (page.width * scale - 1e-9).ceil()).toDouble();
    fullHeight = math.max(1, (page.height * scale - 1e-9).ceil()).toDouble();
    sx = fullWidth / page.width;
    sy = fullHeight / page.height;
    cols = (fullWidth / tileSize).ceil();
    rows = (fullHeight / tileSize).ceil();
  }

  /// Page size in points.
  final Size page;
  final int lod;
  late final double fullWidth, fullHeight;

  /// Pixels per point on each axis.
  late final double sx, sy;
  late final int cols, rows;

  /// A tile's rectangle in pixels of the full page bitmap (edge tiles are
  /// smaller than [tileSize]).
  Rect pixelRect(int tx, int ty) {
    final l = tx * tileSize.toDouble(), t = ty * tileSize.toDouble();
    return Rect.fromLTWH(
      l,
      t,
      math.min(tileSize.toDouble(), fullWidth - l),
      math.min(tileSize.toDouble(), fullHeight - t),
    );
  }

  /// A tile's rectangle in page points (origin top-left of the page).
  Rect pageRect(int tx, int ty) {
    final p = pixelRect(tx, ty);
    return Rect.fromLTRB(p.left / sx, p.top / sy, p.right / sx, p.bottom / sy);
  }

  /// Tile coordinates whose area overlaps [area] (page points).
  Iterable<(int, int)> tilesIn(Rect area) sync* {
    final r = area.intersect(Offset.zero & page);
    if (r.width <= 0 || r.height <= 0) return;
    final c0 = (r.left * sx / tileSize).floor().clamp(0, cols - 1);
    final c1 = ((r.right * sx - 1e-6) / tileSize).floor().clamp(0, cols - 1);
    final r0 = (r.top * sy / tileSize).floor().clamp(0, rows - 1);
    final r1 = ((r.bottom * sy - 1e-6) / tileSize).floor().clamp(0, rows - 1);
    for (var ty = r0; ty <= r1; ty++) {
      for (var tx = c0; tx <= c1; tx++) {
        yield (tx, ty);
      }
    }
  }
}
