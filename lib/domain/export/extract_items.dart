import '../model/models.dart';

/// One entry of the Extract list: a highlight or a note.
abstract interface class ExtractEntry {
  /// Zero-based page number; -1 if on no page (a note placed off every page).
  int get pageIndex;
}

/// One line of the Extract list: a highlight, placed in the document.
class ExtractItem implements ExtractEntry {
  const ExtractItem(this.highlight, this.pageIndex);

  final Highlight highlight;

  /// Zero-based page number; -1 if the page is no longer in the document.
  @override
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

/// A quote a note is linked to.
class LinkedQuote {
  const LinkedQuote({
    required this.highlightId,
    required this.quote,
    required this.pageIndex,
    required this.isRegion,
  });
  final String highlightId, quote;
  final int pageIndex;
  final bool isRegion;

  /// What to show: the quote, or "(image region)".
  String get shown => isRegion ? '(image region)' : quote;
}

/// A note in the Extract list, with the quotes it is linked to.
class ExtractNote implements ExtractEntry {
  const ExtractNote(this.note, this.pageIndex, this.quotes);

  final Note note;
  @override
  final int pageIndex;
  final List<LinkedQuote> quotes;

  String get text => note.text.trim();
  int get pageNumber => pageIndex + 1;
}

/// The notes of a document with text in them (an empty note is not listed),
/// in reading order: by page, then top to bottom, then left to right; notes on
/// no page last. [quotesOf] gives the highlights each note links to, in the
/// order they were linked.
List<ExtractNote> buildNotes(
  Iterable<Note> notes,
  Map<String, int> pageIndexById,
  List<LinkedQuote> Function(String noteId) quotesOf,
) {
  final out = [
    for (final n in notes)
      if (n.text.trim().isNotEmpty)
        ExtractNote(n, pageIndexById[n.pageId] ?? -1, quotesOf(n.id)),
  ];
  out.sort((a, b) {
    final pa = a.pageIndex < 0 ? 1 << 30 : a.pageIndex;
    final pb = b.pageIndex < 0 ? 1 << 30 : b.pageIndex;
    if (pa != pb) return pa.compareTo(pb);
    final y = a.note.y.compareTo(b.note.y);
    if (y != 0) return y;
    final x = a.note.x.compareTo(b.note.x);
    if (x != 0) return x;
    return a.note.id.compareTo(b.note.id);
  });
  return out;
}

/// Highlights and notes in one list: page by page, a page's highlights (in
/// reading order) before its notes; entries on no page last.
List<ExtractEntry> mergeEntries(
  List<ExtractItem> highlights,
  List<ExtractNote> notes,
) {
  final out = <ExtractEntry>[];
  var h = 0, n = 0;
  int key(int page) => page < 0 ? 1 << 30 : page;
  while (h < highlights.length || n < notes.length) {
    if (n >= notes.length) {
      out.add(highlights[h++]);
    } else if (h >= highlights.length) {
      out.add(notes[n++]);
    } else if (key(highlights[h].pageIndex) <= key(notes[n].pageIndex)) {
      out.add(highlights[h++]);
    } else {
      out.add(notes[n++]);
    }
  }
  return out;
}
