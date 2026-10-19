import '../../core/geometry/box.dart';

/// A uniform grid over one page (or the free canvas) that finds the marks
/// near a point or inside an area without looking at all of them (SPEC 5.7).
///
/// Each mark is filed under every cell its box touches. A query visits only
/// the cells its area touches, so the cost depends on how crowded the spot is,
/// not on how many marks the page holds.
class SpatialGrid {
  SpatialGrid({this.cell = 128});

  /// Cell size in page points.
  final double cell;

  final Map<int, Set<String>> _cells = {};
  final Map<String, Box> _boxes = {};

  int get length => _boxes.length;
  bool contains(String id) => _boxes.containsKey(id);
  Box? boxOf(String id) => _boxes[id];

  static int _key(int cx, int cy) =>
      (cx & 0xFFFFFFFF) << 32 | (cy & 0xFFFFFFFF);

  int _c(double v) => (v / cell).floor();

  Iterable<int> _keysFor(Box b) sync* {
    final x0 = _c(b.x0), x1 = _c(b.x1), y0 = _c(b.y0), y1 = _c(b.y1);
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        yield _key(x, y);
      }
    }
  }

  /// Files [id] under [box], replacing an earlier box for the same id.
  void put(String id, Box box) {
    remove(id);
    _boxes[id] = box;
    for (final k in _keysFor(box)) {
      (_cells[k] ??= <String>{}).add(id);
    }
  }

  void remove(String id) {
    final old = _boxes.remove(id);
    if (old == null) return;
    for (final k in _keysFor(old)) {
      final set = _cells[k];
      if (set == null) continue;
      set.remove(id);
      if (set.isEmpty) _cells.remove(k);
    }
  }

  void clear() {
    _cells.clear();
    _boxes.clear();
  }

  /// Ids whose box overlaps [area] (touching counts).
  Set<String> query(Box area) {
    final out = <String>{};
    for (final k in _keysFor(area)) {
      final set = _cells[k];
      if (set == null) continue;
      for (final id in set) {
        if (out.contains(id)) continue;
        final b = _boxes[id]!;
        if (b.x0 <= area.x1 &&
            b.x1 >= area.x0 &&
            b.y0 <= area.y1 &&
            b.y1 >= area.y0) {
          out.add(id);
        }
      }
    }
    return out;
  }
}
