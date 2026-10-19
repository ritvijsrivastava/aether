import '../model/models.dart';

/// One line of the Extract list: a highlight, placed in the document.
class ExtractItem {
  const ExtractItem(this.highlight, this.pageIndex);

  final Highlight highlight;

  /// Zero-based page number; -1 if the page is no longer in the document.
  final int pageIndex;

  Meaning get meaning => highlight.meaning;
  String get quote => highlight.quote;

  /// A rectangle over a figure or scan, with no text behind it.
  bool get isRegion => highlight.startChar < 0;

  /// One-based, as readers count pages.
  int get pageNumber => pageIndex + 1;
}

/// The highlights of a document as an ordered list.
///
/// Reading order: by page, then by position in the page's text, with free
/// rectangles after the text on their page (they have no text position). A
/// highlight whose page is gone sorts last. Ties break on id so the order
/// never flickers.
///
/// [only] keeps a single meaning; null keeps all of them.
List<ExtractItem> buildExtract(
  Iterable<Highlight> highlights,
  Map<String, int> pageIndexById, {
  Meaning? only,
}) {
  final items = [
    for (final h in highlights)
      if (only == null || h.meaning == only)
        ExtractItem(h, pageIndexById[h.pageId] ?? -1),
  ];
  items.sort(_readingOrder);
  return items;
}

int _readingOrder(ExtractItem a, ExtractItem b) {
  final pa = a.pageIndex < 0 ? 1 << 30 : a.pageIndex;
  final pb = b.pageIndex < 0 ? 1 << 30 : b.pageIndex;
  if (pa != pb) return pa.compareTo(pb);
  if (a.isRegion != b.isRegion) return a.isRegion ? 1 : -1;
  if (a.isRegion) {
    // Regions: top to bottom, then left to right.
    final ba = a.highlight.bounds, bb = b.highlight.bounds;
    final y = ba.y0.compareTo(bb.y0);
    if (y != 0) return y;
    final x = ba.x0.compareTo(bb.x0);
    if (x != 0) return x;
  } else {
    final s = a.highlight.startChar.compareTo(b.highlight.startChar);
    if (s != 0) return s;
    final e = a.highlight.endChar.compareTo(b.highlight.endChar);
    if (e != 0) return e;
  }
  return a.highlight.id.compareTo(b.highlight.id);
}
