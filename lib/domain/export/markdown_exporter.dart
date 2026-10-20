import '../model/models.dart';
import 'extract_items.dart';

/// How the Markdown is laid out.
enum MarkdownOrder {
  /// One section per meaning (Claim, Method, Question), each in reading order.
  byMeaning,

  /// One list, in reading order, each line saying which meaning it is.
  readingOrder,
}

/// The Extract list as Markdown (SPEC §10). A pure function of its inputs, so
/// the output is pinned by golden files.
///
/// ```
/// # Title
///
/// ## Claim
/// - "quoted text" (p. 1)
///
/// ## Method
/// - "quoted text" (p. 2)
/// ```
abstract final class MarkdownExporter {
  static String export(
    String title,
    List<ExtractItem> items, {
    MarkdownOrder order = MarkdownOrder.byMeaning,
    List<ExtractNote> notes = const [],
  }) {
    final out = StringBuffer('# ${_title(title)}\n');
    if (items.isEmpty && notes.isEmpty) {
      out.write('\nNothing marked yet.\n');
      return out.toString();
    }
    switch (order) {
      case MarkdownOrder.byMeaning:
        for (final m in Meaning.values) {
          final group = [
            for (final i in items)
              if (i.meaning == m) i,
          ];
          if (group.isEmpty) continue;
          out.write('\n## ${m.label}\n');
          for (final i in group) {
            out.write('- ${_line(i)}${_page(i, '')}\n');
          }
        }
      case MarkdownOrder.readingOrder:
        if (items.isNotEmpty) out.write('\n');
        for (final i in items) {
          out.write('- ${_line(i)}${_page(i, i.meaning.label)}\n');
        }
    }
    if (notes.isNotEmpty) {
      out.write('\n## Notes\n');
      for (final n in notes) {
        out.write('- ${_noteLine(n)}\n');
      }
    }
    return out.toString();
  }

  /// `text (on "quote", p. 2)`: the note's words on one line, then what it is
  /// about and where it sits.
  static String _noteLine(ExtractNote n) {
    final text = n.text.replaceAll(RegExp(r'\s+'), ' ');
    final on = [
      for (final q in n.quotes)
        '${q.isRegion ? '*(image region)*' : '"${q.quote}"'}'
            '${q.pageIndex >= 0 ? ', p. ${q.pageIndex + 1}' : ''}',
    ];
    final where = on.isNotEmpty
        ? '(on ${on.join('; ')})'
        : (n.pageIndex >= 0 ? '(p. ${n.pageNumber})' : '');
    return where.isEmpty ? text : '$text $where';
  }

  /// A title is one line.
  static String _title(String t) {
    final one = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.isEmpty ? 'Untitled' : one;
  }

  static String _line(ExtractItem i) =>
      i.isRegion ? '*(image region)*' : '"${i.quote}"';

  /// ` (p. 3)`, or ` (p. 3, Claim)` when [extra] is given; nothing if the
  /// page is unknown and there is no [extra].
  static String _page(ExtractItem i, String extra) {
    final parts = [
      if (i.pageIndex >= 0) 'p. ${i.pageNumber}',
      if (extra.isNotEmpty) extra,
    ];
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
  }
}
