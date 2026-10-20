import 'dart:io';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/export/extract_items.dart';
import 'package:aether/domain/export/markdown_exporter.dart';
import 'package:aether/domain/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

Highlight hl(String id, String page, int start, String quote, Meaning m) =>
    Highlight(
      id: id,
      docId: 'd',
      pageId: page,
      meaning: m,
      startChar: start,
      endChar: start < 0 ? -1 : start + quote.length,
      quote: quote,
      rects: const [Box(0, 0, 10, 10)],
    );

const pages = {'p0': 0, 'p1': 1, 'p2': 2, 'p3': 3};

/// A small, mixed document, deliberately given out of order.
List<ExtractItem> sample() => buildExtract([
  hl('5', 'p3', 12, 'How does it scale past 2,000 workers?', Meaning.question),
  hl('1', 'p0', 10, 'MapReduce is a programming model.', Meaning.claim),
  hl('3', 'p1', 40, 'The input is split into M pieces.', Meaning.method),
  hl('2', 'p0', 400, 'Programs are automatically parallelized.', Meaning.claim),
  hl('4', 'p1', -1, '(image region)', Meaning.method),
  hl('6', 'p2', 5, 'He said "go" and left.', Meaning.claim),
], pages);

/// Compares with `test/domain/goldens/<name>`. Re-record a deliberate change
/// with `UPDATE_GOLDENS=1 flutter test test/domain/markdown_exporter_test.dart`.
void expectGolden(String name, String actual) {
  final f = File('test/domain/goldens/$name');
  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    f.writeAsStringSync(actual);
    return;
  }
  expect(f.existsSync(), isTrue, reason: 'missing golden $name');
  expect(actual, f.readAsStringSync());
}

List<ExtractNote> sampleNotes() => [
  ExtractNote(
    const Note(
      id: 'n1',
      docId: 'd',
      pageId: 'p1',
      x: 0,
      y: 10,
      text: 'Check\nthe split size.',
    ),
    1,
    const [
      LinkedQuote(
        highlightId: '3',
        quote: 'The input is split into M pieces.',
        pageIndex: 1,
        isRegion: false,
      ),
    ],
  ),
  ExtractNote(
    const Note(
      id: 'n2',
      docId: 'd',
      pageId: 'p2',
      x: 0,
      y: 10,
      text: 'Two sources.',
    ),
    2,
    const [
      LinkedQuote(
        highlightId: '1',
        quote: 'MapReduce is a programming model.',
        pageIndex: 0,
        isRegion: false,
      ),
      LinkedQuote(
        highlightId: '4',
        quote: '(image region)',
        pageIndex: 1,
        isRegion: true,
      ),
    ],
  ),
  ExtractNote(
    const Note(
      id: 'n3',
      docId: 'd',
      pageId: 'p3',
      x: 0,
      y: 10,
      text: 'No links, just a thought.',
    ),
    3,
    const [],
  ),
  ExtractNote(
    const Note(id: 'n4', docId: 'd', x: 0, y: 0, text: 'Off the pages.'),
    -1,
    const [],
  ),
];

void main() {
  test('notes follow the meaning sections, matching their golden file', () {
    expectGolden(
      'export_with_notes.md',
      MarkdownExporter.export('MapReduce', sample(), notes: sampleNotes()),
    );
  });

  test('notes with the reading-order layout', () {
    expectGolden(
      'export_reading_order_with_notes.md',
      MarkdownExporter.export(
        'MapReduce',
        sample(),
        order: MarkdownOrder.readingOrder,
        notes: sampleNotes(),
      ),
    );
  });

  test('only notes: no empty highlight sections, no "Nothing marked yet"', () {
    final md = MarkdownExporter.export(
      'T',
      const [],
      notes: sampleNotes().sublist(2, 3),
    );
    expect(md, '# T\n\n## Notes\n- No links, just a thought. (p. 4)\n');
    final r = MarkdownExporter.export(
      'T',
      const [],
      order: MarkdownOrder.readingOrder,
      notes: sampleNotes().sublist(2, 3),
    );
    expect(r, md);
  });

  test('a note\'s lines are joined into one, and its sources named', () {
    final md = MarkdownExporter.export(
      'T',
      const [],
      notes: sampleNotes().sublist(0, 1),
    );
    expect(
      md,
      '# T\n\n## Notes\n- Check the split size. (on "The input is split into M pieces.", p. 2)\n',
    );
  });

  test('nothing and no notes still says so', () {
    expect(
      MarkdownExporter.export('T', const []),
      '# T\n\nNothing marked yet.\n',
    );
  });

  test('grouped by meaning matches its golden file', () {
    expectGolden(
      'export_by_meaning.md',
      MarkdownExporter.export('MapReduce', sample()),
    );
  });

  test('reading order matches its golden file', () {
    expectGolden(
      'export_reading_order.md',
      MarkdownExporter.export(
        'MapReduce',
        sample(),
        order: MarkdownOrder.readingOrder,
      ),
    );
  });

  test('sections appear in the order Claim, Method, Question', () {
    final md = MarkdownExporter.export('T', sample());
    expect(md.indexOf('## Claim'), lessThan(md.indexOf('## Method')));
    expect(md.indexOf('## Method'), lessThan(md.indexOf('## Question')));
  });

  test('a meaning with nothing marked has no section', () {
    final md = MarkdownExporter.export('T', [
      ExtractItem(hl('a', 'p0', 1, 'Only a claim.', Meaning.claim), 0),
    ]);
    expect(md, '# T\n\n## Claim\n- "Only a claim." (p. 1)\n');
    expect(md, isNot(contains('## Method')));
  });

  test('nothing marked says so', () {
    expect(
      MarkdownExporter.export('Empty paper', const []),
      '# Empty paper\n\nNothing marked yet.\n',
    );
  });

  test('a free rectangle is listed as an image region, not a quote', () {
    final md = MarkdownExporter.export('T', [
      ExtractItem(hl('r', 'p1', -1, '(image region)', Meaning.method), 1),
    ]);
    expect(md, contains('- *(image region)* (p. 2)'));
    expect(md, isNot(contains('"(image region)"')));
  });

  test('a highlight on a page that is gone omits the page', () {
    final md = MarkdownExporter.export('T', [
      ExtractItem(hl('x', 'gone', 1, 'Orphan.', Meaning.claim), -1),
    ]);
    expect(md, contains('- "Orphan."\n'));
  });

  test('the title is one tidy line', () {
    expect(
      MarkdownExporter.export('  A\n  long   title ', const []),
      startsWith('# A long title\n'),
    );
    expect(
      MarkdownExporter.export('   ', const []),
      startsWith('# Untitled\n'),
    );
  });

  test('ends with exactly one newline', () {
    final md = MarkdownExporter.export('T', sample());
    expect(md.endsWith('\n'), isTrue);
    expect(md.endsWith('\n\n'), isFalse);
  });
}
