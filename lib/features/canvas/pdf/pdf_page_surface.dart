import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, Listenable, debugPrint;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../engine/page_surface.dart';
import '../engine/scene.dart';
import 'lru_cache.dart';
import 'tile_math.dart';
import 'tile_scheduler.dart';

/// Memory budget for cached tiles, by device class (SPEC §5.3).
int tileCacheBytesFor({
  required bool isDesktop,
  required double shortestSideDp,
}) {
  const mb = 1024 * 1024;
  if (isDesktop) return 384 * mb;
  return shortestSideDp < 600 ? 128 * mb : 192 * mb;
}

class _Tile {
  _Tile(this.tile, this.arrivedMs);
  final TileImage tile;

  /// When it arrived, on the surface's clock, for the crossfade.
  final int arrivedMs;
}

/// Draws PDF pages from cached tiles.
///
/// Per frame it works out which tiles the view needs, draws those it has,
/// stands in a coarser tile (scaled up) for those it does not, and asks the
/// scheduler for the missing ones, nearest the viewport centre first. A
/// one-tile whole-page "base" image is always fetched first, so there is
/// never blank paper, only soft paper that sharpens.
class PdfPageSurface extends ChangeNotifier implements PageSurface {
  PdfPageSurface({
    required this.pageSizes,
    required TileRenderer renderer,
    int cacheBytes = 192 * 1024 * 1024,
    int maxConcurrent = 2,
    this.fadeMs = 140,
  }) {
    _cache = LruBytesCache<TileKey, _Tile>(
      maxBytes: cacheBytes,
      onEvict: (_, t) => t.tile.dispose(),
    );
    _scheduler = TileScheduler(
      renderer: renderer,
      onTile: _onTile,
      maxConcurrent: maxConcurrent,
      onError: (key, e) => debugPrint('Tile $key failed: $e'),
    );
  }

  /// Page sizes in points, by page index.
  final List<Size> pageSizes;
  final int fadeMs;

  late final LruBytesCache<TileKey, _Tile> _cache;
  late final TileScheduler _scheduler;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<TileKey, double> _wanted = {};
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;
  bool _fading = false;
  bool _disposed = false;

  // Priority bands: whole-page base tiles, then visible tiles, then prefetch.
  // Within a band, nearer the viewport centre (in screen px) is first.
  static const double _bandVisible = 1e6, _bandPrefetch = 2e6;

  int get cachedTiles => _cache.length;
  int get cachedBytes => _cache.bytes;
  TileScheduler get scheduler => _scheduler;

  @override
  Listenable? get repaint => this;

  @override
  String? get stats {
    final total = _cache.hits + _cache.misses;
    final hit = total == 0 ? 100 : (_cache.hits * 100 / total).round();
    return 'tiles ${_cache.length} · ${(_cache.bytes / 1048576).toStringAsFixed(0)} MB'
        ' · hit $hit%'
        ' · rendering ${_scheduler.active} queued ${_scheduler.queued}'
        '${_scheduler.failed > 0 ? ' · failed ${_scheduler.failed}' : ''}';
  }

  @override
  void beginFrame() {
    _cache.beginFrame();
    _wanted.clear();
    _fading = false;
  }

  @override
  void paint(Canvas canvas, Card card, PageViewInfo info) {
    if (card.index >= pageSizes.length) return;
    final size = pageSizes[card.index];
    final vis = info.viewportWorld
        .intersect(card.rect)
        .shift(-card.rect.topLeft);
    if (vis.width <= 0 || vis.height <= 0) return;

    final scale = info.zoom * info.devicePixelRatio;
    final baseLod = TileMath.baseLod(size);
    // Never render coarser than the whole-page base tile: zoomed far out the
    // base tile, scaled down, is the right picture.
    final lod = math.max(TileMath.lodFor(scale, size), baseLod);
    final geo = TileGeometry(size, lod);
    final origin = card.rect.topLeft;
    final centre = info.viewportWorld.center;
    final now = _clock.elapsedMilliseconds;
    // Half a device pixel of overlap hides hairline seams between tiles.
    final seam = 0.5 / scale;

    double dist(Rect worldRect) =>
        (worldRect.center - centre).distance * info.zoom;

    // The whole-page base tile(s): fetched first, and kept alive (touched) so
    // there is always something to fall back on.
    final baseGeo = TileGeometry(size, baseLod);
    for (final (tx, ty) in baseGeo.tilesIn(Offset.zero & size)) {
      final key = TileKey(card.index, baseLod, tx, ty);
      if (_cache.get(key) == null) {
        _wanted[key] = dist(baseGeo.pageRect(tx, ty).shift(origin)) * 1e-3;
      }
    }

    // Visible tiles at the wanted level of detail.
    final drawn = <(int, int)>{};
    for (final (tx, ty) in geo.tilesIn(vis)) {
      drawn.add((tx, ty));
      final key = TileKey(card.index, lod, tx, ty);
      final worldRect = geo.pageRect(tx, ty).shift(origin);
      final t = _cache.get(key);
      if (t == null) {
        _drawFallback(canvas, card, size, key, geo, baseLod);
        if (lod != baseLod) _wanted[key] = _bandVisible + dist(worldRect);
        continue;
      }
      final a = fadeMs <= 0
          ? 1.0
          : ((now - t.arrivedMs) / fadeMs).clamp(0.0, 1.0);
      if (a < 1) {
        _fading = true;
        _drawFallback(canvas, card, size, key, geo, baseLod);
      }
      _paint.color = Color.fromARGB((a * 255).round(), 255, 255, 255);
      final img = t.tile.image;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        worldRect.inflate(seam),
        _paint,
      );
    }

    // Prefetch a ring just outside the viewport so scrolling finds tiles
    // ready instead of waiting for them.
    final ring = tileSize / scale * 0.75;
    for (final (tx, ty) in geo.tilesIn(vis.inflate(ring))) {
      if (drawn.contains((tx, ty))) continue;
      final key = TileKey(card.index, lod, tx, ty);
      if (_cache.containsKey(key)) {
        _cache.get(key); // keep it
      } else if (lod != baseLod) {
        _wanted[key] = _bandPrefetch + dist(geo.pageRect(tx, ty).shift(origin));
      }
    }
  }

  /// Stands in the finest cached coarser level that fully covers [key]'s
  /// area, scaled up. Draws nothing if none is cached yet.
  void _drawFallback(
    Canvas canvas,
    Card card,
    Size size,
    TileKey key,
    TileGeometry geo,
    int baseLod,
  ) {
    final area = geo.pageRect(key.tx, key.ty);
    _paint.color = const Color(0xFFFFFFFF);
    for (var l = key.lod - 1; l >= baseLod; l--) {
      final g = TileGeometry(size, l);
      final covering = g.tilesIn(area).toList();
      if (covering.isEmpty) continue;
      if (!covering.every(
        (c) => _cache.containsKey(TileKey(key.page, l, c.$1, c.$2)),
      )) {
        continue;
      }
      for (final (tx, ty) in covering) {
        final t = _cache.get(TileKey(key.page, l, tx, ty))!;
        final cr = g.pageRect(tx, ty);
        final inter = cr.intersect(area);
        if (inter.width <= 0 || inter.height <= 0) continue;
        canvas.drawImageRect(
          t.tile.image,
          Rect.fromLTRB(
            (inter.left - cr.left) * g.sx,
            (inter.top - cr.top) * g.sy,
            (inter.right - cr.left) * g.sx,
            (inter.bottom - cr.top) * g.sy,
          ),
          inter.shift(card.rect.topLeft),
          _paint,
        );
      }
      return;
    }
  }

  @override
  void endFrame() {
    _scheduler.want(_wanted);
    _cache.endFrame();
    if (_fading && !_disposed) {
      // Keep frames coming while tiles are mid-crossfade.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  void _onTile(TileKey key, TileImage tile) {
    if (_disposed) {
      tile.dispose();
      return;
    }
    _cache.put(key, _Tile(tile, _clock.elapsedMilliseconds), tile.bytes);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduler.dispose();
    _cache.clear();
    super.dispose();
  }
}
