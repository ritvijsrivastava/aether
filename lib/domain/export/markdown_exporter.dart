import '../marks/colour_name.dart';
import 'extract_items.dart';

/// How the Markdown is laid out.
enum MarkdownOrder {
  /// One section per colour, in order of first use, each in reading order.
  byColour,

  /// One list, in reading order, each line saying which colour it is.
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
    MarkdownOrder order = MarkdownOrder.byColour,
    List<ExtractNote> notes = const [],
  }) {
    final out = StringBuffer('# ${_title(title)}\n');
    if (items.isEmpty && notes.isEmpty) {
      out.write('\nNothing marked yet.\n');
      return out.toString();
    }
    switch (order) {
      case MarkdownOrder.byColour:
        final labels = colourLabels(items);
        for (final c in labels.keys) {
          out.write('\n## ${labels[c]}\n');
          for (final i in items) {
            if (i.color == c) out.write('- ${_line(i)}${_page(i, '')}\n');
          }
        }
      case MarkdownOrder.readingOrder:
        if (items.isNotEmpty) out.write('\n');
        for (final i in items) {
          out.write(
            '- ${_line(i)}${_page(i, colourLabels(items)[i.color]!)}\n',
          );
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

  /// The colours in use, in order of first use among [items] (which are in
  /// reading order), each with its automatic label; two colours that round to
  /// the same name get " 2", " 3" after it so headings stay distinct.
  static Map<int, String> colourLabels(List<ExtractItem> items) {
    final out = <int, String>{};
    final used = <String, int>{};
    for (final i in items) {
      if (out.containsKey(i.color)) continue;
      final base = colourName(i.color);
      final n = (used[base] ?? 0) + 1;
      used[base] = n;
      out[i.color] = n == 1 ? base : '$base $n';
    }
    return out;
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
