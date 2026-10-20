import '../model/models.dart';
import '../text/text_selection.dart';

/// What to do when the owner marks [selection] in [color].
sealed class HighlightPlan {
  const HighlightPlan();
}

/// Already highlighted in this colour: do nothing, point at [existing].
class HighlightDuplicate extends HighlightPlan {
  const HighlightDuplicate(this.existing);
  final Highlight existing;
}

/// The same words are highlighted in another colour: change that colour.
class HighlightRecolor extends HighlightPlan {
  const HighlightRecolor(this.existing);
  final Highlight existing;
}

/// Overlaps highlights of the same colour: replace them with one covering
/// the union of their ranges and the new one.
class HighlightMerge extends HighlightPlan {
  const HighlightMerge(this.absorbed, this.start, this.end);
  final List<Highlight> absorbed;
  final int start, end;
}

/// Nothing to reconcile: add it as it is. (Highlights of different colours
/// may overlap; they stack.)
class HighlightAdd extends HighlightPlan {
  const HighlightAdd();
}

/// Decides what marking [selection] in [color] means, given the highlights
/// already on the same page ([onPage]).
///
/// 1. Inside a highlight of the same colour already: a duplicate.
/// 2. Overlapping highlights of the same colour: merge them into one.
/// 3. Exactly the words of a highlight of another colour: recolour that one.
/// 4. Anything else: add.
///
/// Free rectangles over figures (no text) are only a duplicate when the same
/// rectangle exists in the same colour.
HighlightPlan planHighlight(
  Iterable<Highlight> onPage,
  MarkSelection selection,
  int color,
) {
  if (selection.isRegion) {
    final b = selection.bounds;
    for (final h in onPage) {
      if (h.startChar < 0 && h.color == color && h.bounds == b) {
        return HighlightDuplicate(h);
      }
    }
    return const HighlightAdd();
  }
  final s = selection.start, e = selection.end;
  final same = <Highlight>[];
  Highlight? exactOther;
  for (final h in onPage) {
    if (h.startChar < 0) continue;
    final overlaps = h.startChar < e && s < h.endChar;
    if (!overlaps) continue;
    if (h.color == color) {
      if (h.startChar <= s && h.endChar >= e) return HighlightDuplicate(h);
      same.add(h);
    } else if (h.startChar == s && h.endChar == e) {
      exactOther ??= h;
    }
  }
  if (same.isNotEmpty) {
    var lo = s, hi = e;
    for (final h in same) {
      if (h.startChar < lo) lo = h.startChar;
      if (h.endChar > hi) hi = h.endChar;
    }
    return HighlightMerge(same, lo, hi);
  }
  if (exactOther != null) return HighlightRecolor(exactOther);
  return const HighlightAdd();
}
