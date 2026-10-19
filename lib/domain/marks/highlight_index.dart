import '../../core/geometry/box.dart';
import '../model/models.dart';
import 'spatial_grid.dart';

/// Finds the highlight under a pointer.
///
/// Thin text highlights must stay easy to hit (DESIGN: "minimum 16px height"),
/// so each line rect is grown on screen, not on the page: by [tolerancePx] all
/// round, and vertically up to [minHeightPx] in total. Both are divided by the
/// zoom, so the reach is the same number of screen pixels at any zoom.
class HighlightIndex {
  HighlightIndex({this.cell = 128});

  static const double tolerancePx = 10;
  static const double minHeightPx = 16;

  final double cell;
  final Map<String, SpatialGrid> _pages = {};
  final Map<String, Highlight> _byId = {};

  /// Insertion order, so that of two equally good hits the later one wins.
  final Map<String, int> _order = {};
  int _n = 0;

  void put(Highlight h) {
    remove(h.id);
    final page = h.pageId;
    if (page == null || h.rects.isEmpty) return;
    _byId[h.id] = h;
    _order[h.id] = _n++;
    (_pages[page] ??= SpatialGrid(cell: cell)).put(h.id, h.bounds);
  }

  void remove(String id) {
    final h = _byId.remove(id);
    _order.remove(id);
    if (h?.pageId != null) _pages[h!.pageId]?.remove(id);
  }

  void clear() {
    _pages.clear();
    _byId.clear();
    _order.clear();
  }

  /// The highlight at page point ([x], [y]) when the view is at [zoom], or
  /// null. Where several are hit, the one with the smallest area wins (a
  /// single word beats the sentence around it), then the newest.
  Highlight? hitTest(String pageId, double x, double y, double zoom) {
    final grid = _pages[pageId];
    if (grid == null) return null;
    final tol = tolerancePx / zoom;
    final minH = minHeightPx / zoom;
    // Candidates: anything whose bounds reach within the largest growth.
    final reach = tol > minH ? tol : minH;
    final near = grid.query(Box(x - reach, y - reach, x + reach, y + reach));
    Highlight? best;
    var bestArea = double.infinity;
    var bestOrder = -1;
    for (final id in near) {
      final h = _byId[id]!;
      var hit = false;
      var area = 0.0;
      for (final r in h.rects) {
        area += r.width * r.height;
        final dy = (minH - r.height) / 2 > tol ? (minH - r.height) / 2 : tol;
        if (x >= r.x0 - tol &&
            x <= r.x1 + tol &&
            y >= r.y0 - dy &&
            y <= r.y1 + dy) {
          hit = true;
        }
      }
      if (!hit) continue;
      final order = _order[id]!;
      if (area < bestArea || (area == bestArea && order > bestOrder)) {
        best = h;
        bestArea = area;
        bestOrder = order;
      }
    }
    return best;
  }
}
