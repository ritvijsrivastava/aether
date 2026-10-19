import 'dart:ui';

import 'package:meta/meta.dart';

/// One document page as a movable card, in world space.
@immutable
class Card {
  const Card({required this.id, required this.index, required this.rect});

  final String id;

  /// Zero-based page number within the document.
  final int index;
  final Rect rect;

  Card moved(Offset delta) =>
      Card(id: id, index: index, rect: rect.shift(delta));
}

/// The cards on the desk. Immutable; the controller swaps whole scenes.
@immutable
class Scene {
  const Scene(this.cards);

  /// Cards in one column, top to bottom, [gap] apart, centred on a shared
  /// vertical axis so mixed page widths read as one document.
  factory Scene.column(
    List<Size> pageSizes, {
    double gap = 80,
    String Function(int index)? idOf,
  }) {
    final widest = pageSizes.fold<double>(
      0,
      (m, s) => s.width > m ? s.width : m,
    );
    var y = 0.0;
    final cards = <Card>[];
    for (var i = 0; i < pageSizes.length; i++) {
      final s = pageSizes[i];
      cards.add(
        Card(
          id: idOf?.call(i) ?? 'page-$i',
          index: i,
          rect: Rect.fromLTWH((widest - s.width) / 2, y, s.width, s.height),
        ),
      );
      y += s.height + gap;
    }
    return Scene(cards);
  }

  final List<Card> cards;

  bool get isEmpty => cards.isEmpty;

  /// Bounding box of all cards (empty rect when there are none).
  Rect get bounds {
    if (cards.isEmpty) return Rect.zero;
    var r = cards.first.rect;
    for (final c in cards) {
      r = r.expandToInclude(c.rect);
    }
    return r;
  }

  Card? byId(String id) {
    for (final c in cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Cards whose rect intersects [world]. Linear: a 500-page row is a few
  /// microseconds, far below the cost of drawing even one tile.
  Iterable<Card> visible(Rect world) sync* {
    for (final c in cards) {
      if (c.rect.overlaps(world)) yield c;
    }
  }

  /// The card nearest [world] point (by centre), for "fit this page".
  Card? nearest(Offset point) {
    Card? best;
    var bestD = double.infinity;
    for (final c in cards) {
      final d = (c.rect.center - point).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  Scene withCardMoved(String id, Offset delta) =>
      Scene([for (final c in cards) c.id == id ? c.moved(delta) : c]);
}
