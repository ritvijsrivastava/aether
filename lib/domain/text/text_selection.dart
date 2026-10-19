import 'dart:math' as math;

import '../../core/geometry/box.dart';
import 'page_text.dart';

/// The shown quote of a free-rectangle highlight (SPEC §6.2 fallback).
const imageRegionQuote = '(image region)';

/// A highlight in the making: what the Mark tool previews while dragging and
/// stores on release.
class MarkSelection {
  const MarkSelection({
    required this.start,
    required this.end,
    required this.rects,
    required this.quote,
    this.isRegion = false,
  });

  /// Character range `[start, end)` on the page. `-1, -1` for a region.
  final int start, end;

  /// One rect per visual line (page space); a single rect for a region.
  final List<Box> rects;
  final String quote;

  /// A free rectangle over a figure or scanned page, with no text anchor.
  final bool isRegion;

  Box get bounds => rects.reduce((a, b) => a.union(b));

  @override
  String toString() =>
      'MarkSelection(${isRegion ? 'region' : '$start..$end'}, "$quote")';
}

/// Hit-testing, range building and line rects over a [PageText].
///
/// Pure functions of the page text and page-space points; the canvas turns
/// pointer positions into page space and chooses the tolerance in points
/// (about 10 dp divided by the zoom).
abstract final class TextSelector {
  /// The word under or within [tolerance] points of ([x], [y]), or -1.
  /// A point inside several overlapping words (a superscript over its base)
  /// goes to the smallest one.
  static int wordAt(PageText t, double x, double y, {double tolerance = 8}) {
    var best = -1;
    var bestD = double.infinity;
    var bestArea = double.infinity;
    for (final line in t.lines) {
      if (_distance(line.box, x, y) > tolerance) continue;
      for (var i = line.firstWord; i < line.endWord; i++) {
        final b = t.words[i].box;
        final d = _distance(b, x, y);
        if (d > tolerance) continue;
        final area = b.width * b.height;
        if (d < bestD || (d == bestD && area < bestArea)) {
          best = i;
          bestD = d;
          bestArea = area;
        }
      }
    }
    return best;
  }

  /// The word nearest to a point, with no tolerance limit: the one a drag
  /// extends to when the pointer is in a margin, a gutter or between lines.
  /// Picks the nearest line (so side-by-side columns work), then the nearest
  /// word on it. -1 only if the page has no words.
  static int wordNear(PageText t, double x, double y) {
    var line = -1;
    var lineD = double.infinity;
    for (var l = 0; l < t.lines.length; l++) {
      final d = _distance(t.lines[l].box, x, y);
      if (d < lineD) {
        line = l;
        lineD = d;
      }
    }
    if (line < 0) return -1;
    final tl = t.lines[line];
    var best = tl.firstWord;
    var bestD = double.infinity;
    for (var i = tl.firstWord; i < tl.endWord; i++) {
      final b = t.words[i].box;
      // Along the line, distance in x only: a point above or below a line
      // still belongs to the word it is over.
      final d = x < b.x0 ? b.x0 - x : (x > b.x1 ? x - b.x1 : 0.0);
      if (d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  /// The selection from word [a] to word [b], inclusive, in either order.
  static MarkSelection? between(PageText t, int a, int b) {
    if (a < 0 || b < 0 || a >= t.words.length || b >= t.words.length) {
      return null;
    }
    final lo = math.min(a, b), hi = math.max(a, b);
    return fromRange(t, t.words[lo].start, t.words[hi].end);
  }

  /// The selection for characters `[start, end)`, or null if it covers no
  /// word.
  static MarkSelection? fromRange(PageText t, int start, int end) {
    final rects = rectsFor(t, start, end);
    if (rects.isEmpty) return null;
    return MarkSelection(
      start: start,
      end: end,
      rects: rects,
      quote: t.quote(start, end),
    );
  }

  /// The sentence containing word [w]. A sentence ends at a word ending in
  /// `.`, `!` or `?` (closing quotes and brackets allowed) that is followed by
  /// an upper-case letter, digit or opening quote, or by nothing; a heading or
  /// paragraph break also ends one. Common abbreviations, single initials and
  /// numbered items do not end one. Never leaves the page.
  static MarkSelection? sentenceAt(PageText t, int w) {
    if (w < 0 || w >= t.words.length) return null;
    final text = [for (final word in t.words) t.quote(word.start, word.end)];
    var first = w;
    while (first > 0 && !_endsSentence(t, text, first - 1)) {
      first--;
    }
    var last = w;
    while (last < t.words.length - 1 && !_endsSentence(t, text, last)) {
      last++;
    }
    return between(t, first, last);
  }

  /// One rect per line for the characters `[start, end)`, snapped to the
  /// line's own top and bottom so a multi-line highlight has even rows. The
  /// first and last words are clipped to the range at character precision.
  static List<Box> rectsFor(PageText t, int start, int end) {
    final s = math.max(0, start), e = math.min(t.length, end);
    if (s >= e) return const [];
    final out = <Box>[];
    var w = t.firstWordEndingAfter(s);
    while (w < t.words.length && t.words[w].start < e) {
      final lineIndex = t.words[w].line;
      final line = t.lines[lineIndex];
      Box? span;
      var allOutliers = true;
      final band = _band(t, line);
      var k = w;
      while (k < line.endWord && t.words[k].start < e) {
        final word = t.words[k];
        final a = math.max(s, word.start), b = math.min(e, word.end);
        final box = (a == word.start && b == word.end)
            ? word.box
            : _charsBox(t, a, b);
        if (box != null) {
          span = span == null ? box : span.union(box);
          if (box.height <= _outlier * band.height) allOutliers = false;
        }
        k++;
      }
      w = k;
      if (span == null) continue;
      final row = allOutliers ? span : Box(span.x0, band.y0, span.x1, band.y1);
      out.add(_atLeastTall(row));
    }
    return out;
  }

  // ── free rectangle fallback ────────────────────────────────────────────

  /// A rectangle highlight with no text behind it.
  static MarkSelection? region(double x0, double y0, double x1, double y1) {
    final box = Box(
      math.min(x0, x1),
      math.min(y0, y1),
      math.max(x0, x1),
      math.max(y0, y1),
    );
    if (box.width < minRegionSize || box.height < minRegionSize) return null;
    return MarkSelection(
      start: -1,
      end: -1,
      rects: [box],
      quote: imageRegionQuote,
      isRegion: true,
    );
  }

  /// Smaller than this (points), a dragged rectangle is a slip, not a mark.
  static const minRegionSize = 4.0;

  // ── helpers ────────────────────────────────────────────────────────────

  /// A highlight row is never thinner than this (points). A line made only of
  /// a dash, a fraction bar or an overline has a glyph box a fraction of a
  /// point tall; the row must still be visible and hittable.
  static const minRowHeight = 6.0;

  static Box _atLeastTall(Box b) {
    if (b.height >= minRowHeight) return b;
    final mid = (b.y0 + b.y1) / 2;
    return Box(b.x0, mid - minRowHeight / 2, b.x1, mid + minRowHeight / 2);
  }

  /// Words taller than this many band heights are not part of the band.
  static const _outlier = 1.5;

  /// The vertical extent of a line's normal-sized words: what a highlight
  /// snaps to. Tall glyphs (integral signs, big brackets) are left out so one
  /// of them does not make the whole row of highlight tall.
  static Box _band(PageText t, TextLine line) {
    final heights = <double>[
      for (var i = line.firstWord; i < line.endWord; i++) t.words[i].box.height,
    ]..sort();
    final median = heights[heights.length >> 1];
    Box? band;
    for (var i = line.firstWord; i < line.endWord; i++) {
      final b = t.words[i].box;
      if (b.height > _outlier * median) continue;
      band = band == null ? b : band.union(b);
    }
    return band ?? line.box;
  }

  static Box? _charsBox(PageText t, int a, int b) {
    Box? out;
    for (var i = a; i < b; i++) {
      if (!t.isVisible(i)) continue;
      final c = t.boxAt(i);
      out = out == null ? c : out.union(c);
    }
    return out;
  }

  static double _distance(Box b, double x, double y) {
    final dx = x < b.x0 ? b.x0 - x : (x > b.x1 ? x - b.x1 : 0.0);
    final dy = y < b.y0 ? b.y0 - y : (y > b.y1 ? y - b.y1 : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  static final _closers = RegExp(r'''["'”’)\]]+$''');
  static final _openers = RegExp(r'''^["'“‘(\[]*[A-Z0-9]''');
  static const _abbreviations = {
    'e.g.',
    'i.e.',
    'cf.',
    'et',
    'al.',
    'fig.',
    'figs.',
    'eq.',
    'eqs.',
    'sec.',
    'secs.',
    'thm.',
    'prop.',
    'lem.',
    'cor.',
    'def.',
    'ref.',
    'refs.',
    'no.',
    'vol.',
    'pp.',
    'p.',
    'vs.',
    'etc.',
    'dr.',
    'mr.',
    'mrs.',
    'ms.',
    'prof.',
    'approx.',
    'resp.',
    'ch.',
    'tab.',
  };

  /// Whether the sentence ends at word [i] (so [i] + 1 starts a new one).
  /// Besides punctuation, a paragraph or heading break ends it: the next
  /// line is more than most of a line height below, or jumps back up the page
  /// (a new column).
  static bool _endsSentence(PageText t, List<String> text, int i) {
    if (i + 1 < t.words.length && t.words[i].line != t.words[i + 1].line) {
      final cur = t.lines[t.words[i].line].box;
      final next = t.lines[t.words[i + 1].line].box;
      if (next.y0 - cur.y1 > 0.8 * cur.height) return true;
      if (next.y0 < cur.y0 - 0.5 * cur.height) return true;
    }
    final word = text[i].replaceFirst(_closers, '');
    if (word.isEmpty) return false;
    final last = word[word.length - 1];
    if (last != '.' && last != '!' && last != '?') return false;
    if (i + 1 >= text.length) return true;
    if (!_openers.hasMatch(text[i + 1])) return false;
    if (last != '.') return true;
    final lower = word.toLowerCase();
    if (_abbreviations.contains(lower)) return false;
    // "J." and "3." are initials and list numbers, not sentence ends.
    final body = word.substring(0, word.length - 1);
    if (body.length == 1) return false;
    if (RegExp(r'^\d+$').hasMatch(body)) return false;
    return true;
  }
}

/// One Mark-tool drag, from pointer-down to release.
///
/// Down on (or near) a word starts a text selection that [update] extends to
/// the nearest word under the pointer, across lines. Down on empty paper
/// (no word within tolerance, or a page with no text at all) starts a free
/// rectangle instead. A tap, with no [update], selects just the word.
class MarkDrag {
  MarkDrag(this.text, this.downX, this.downY, {double tolerance = 8})
    : _anchor = TextSelector.wordAt(text, downX, downY, tolerance: tolerance) {
    _current = _initial();
  }

  final PageText text;
  final double downX, downY;
  final int _anchor;
  MarkSelection? _current;

  /// True if this drag selects text; false for a free rectangle.
  bool get isText => _anchor >= 0;

  /// The word the drag started on, or -1 for a free rectangle.
  int get anchorWord => _anchor;

  /// The selection as it stands: the word under the pointer-down, or null for
  /// a rectangle that has not grown yet.
  MarkSelection? get selection => _current;

  MarkSelection? _initial() =>
      isText ? TextSelector.between(text, _anchor, _anchor) : null;

  /// Moves the free end to ([x], [y]) and returns the new selection.
  MarkSelection? update(double x, double y) {
    if (isText) {
      final head = TextSelector.wordNear(text, x, y);
      _current = TextSelector.between(text, _anchor, head < 0 ? _anchor : head);
    } else {
      _current = TextSelector.region(downX, downY, x, y);
    }
    return _current;
  }
}
