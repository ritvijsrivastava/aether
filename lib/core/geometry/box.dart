import 'package:meta/meta.dart';

/// Axis-aligned rectangle in page space (PDF points, origin top-left, y down).
///
/// Pure Dart so the domain layer needs no Flutter imports.
@immutable
class Box {
  const Box(this.x0, this.y0, this.x1, this.y1);

  factory Box.fromJson(List<dynamic> j) => Box(
    (j[0] as num).toDouble(),
    (j[1] as num).toDouble(),
    (j[2] as num).toDouble(),
    (j[3] as num).toDouble(),
  );

  final double x0, y0, x1, y1;

  double get width => x1 - x0;
  double get height => y1 - y0;

  Box union(Box o) => Box(
    x0 < o.x0 ? x0 : o.x0,
    y0 < o.y0 ? y0 : o.y0,
    x1 > o.x1 ? x1 : o.x1,
    y1 > o.y1 ? y1 : o.y1,
  );

  List<double> toJson() => [x0, y0, x1, y1];

  @override
  bool operator ==(Object other) =>
      other is Box &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.x1 == x1 &&
      other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);

  @override
  String toString() => 'Box($x0, $y0, $x1, $y1)';
}
