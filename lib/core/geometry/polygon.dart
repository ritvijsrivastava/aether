/// Whether the point ([x], [y]) is inside the polygon whose corners are the
/// `x, y` pairs in [xy] (the closing edge is implied), by the even-odd rule.
bool pointInPolygon(double x, double y, List<double> xy) {
  final n = xy.length ~/ 2;
  if (n < 3) return false;
  var inside = false;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final xi = xy[i * 2], yi = xy[i * 2 + 1];
    final xj = xy[j * 2], yj = xy[j * 2 + 1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}
