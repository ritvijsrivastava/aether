import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/links/links_layer.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
import 'package:aether/features/canvas/notes/notes_layer.dart';
import 'package:aether/features/extract/extract_controller.dart';
import 'package:aether/features/extract/extract_panel.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Highlight hl(
  String id,
  String page,
  int start,
  String quote, {
  int m = Swatch.claim,
}) => Highlight(
  id: id,
  docId: 'd',
  pageId: page,
  color: m,
  startChar: start,
  endChar: start < 0 ? -1 : start + quote.length,
  quote: quote,
  rects: const [Box(0, 0, 10, 10)],
);

void main() {
  late HighlightLayer layer;
  late ValueNotifier<Scene> scene;
  late List<String> jumped, deleted;
  late int undone;
  late ExtractController source;

  setUp(() {
    layer = HighlightLayer();
    scene = ValueNotifier(
      Scene.column(const [Size(100, 100), Size(100, 100)], idOf: (i) => 'p$i'),
    );
    jumped = [];
    deleted = [];
    undone = 0;
    source = ExtractController(
      highlights: layer,
      scene: scene,
      onJump: (h) => jumped.add(h.id),
      onDelete: (h) {
        deleted.add(h.id);
        layer.remove(h.id);
      },
      onUndo: () => undone++,
    );
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    ExtractController? withSource,
    double width = 340,
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tokens = brightness == Brightness.dark
        ? AetherTokens.dark
        : AetherTokens.light;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(tokens),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 700,
                  child: ExtractPanel(source: withSource ?? source),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('with nothing marked it says how to start', (tester) async {
    await pump(tester);
    expect(find.text('0 items'), findsOneWidget);
    expect(
      find.textContaining('Highlight or write to start collecting'),
      findsOneWidget,
    );
  });

  testWidgets('without a document it is the same empty panel', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: const Scaffold(body: ExtractPanel()),
        ),
      ),
    );
    expect(find.text('0 items'), findsOneWidget);
  });

  testWidgets('lists highlights in reading order with colour and page', (
    tester,
  ) async {
    layer
      ..add(hl('c', 'p1', 5, 'Third quote', m: Swatch.question))
      ..add(hl('a', 'p0', 90, 'Second quote', m: Swatch.method))
      ..add(hl('b', 'p0', 10, 'First quote'));
    await pump(tester);
    expect(find.text('3 items'), findsOneWidget);
    final order = [
      for (final t in tester.widgetList<Text>(find.textContaining(' quote')))
        t.data,
    ];
    expect(order, ['First quote', 'Second quote', 'Third quote']);
    expect(find.byType(FilterChip), findsNWidgets(5)); // All, 3 colours, Notes
    expect(find.text('p. 1'), findsNWidgets(2));
    expect(find.text('p. 2'), findsOneWidget);
  });

  testWidgets('one item reads "1 item"', (tester) async {
    layer.add(hl('a', 'p0', 1, 'Only one'));
    await pump(tester);
    expect(find.text('1 item'), findsOneWidget);
  });

  testWidgets('a filter chip narrows the list and the count', (tester) async {
    layer
      ..add(hl('a', 'p0', 1, 'A claim'))
      ..add(hl('b', 'p0', 20, 'A method', m: Swatch.method))
      ..add(hl('c', 'p0', 40, 'A question', m: Swatch.question));
    final c = await pump(tester);
    // One chip per colour in use, in reading order, each with its count.
    expect(find.byType(FilterChip), findsNWidgets(5)); // All, 3 colours, Notes
    await tester.tap(find.bySemanticsLabel('Amber, 1 highlights').first);
    await tester.pump();
    expect(c.read(canvasUiProvider).filter, ExtractFilter.colour(Swatch.amber));
    expect(find.text('A method'), findsOneWidget);
    expect(find.text('A claim'), findsNothing);
    expect(find.text('1 item'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pump();
    expect(find.text('3 items'), findsOneWidget);
  });

  testWidgets('any colour gets a chip with its count; chips follow the list', (
    tester,
  ) async {
    layer
      ..add(hl('a', 'p0', 1, 'Teal one', m: 0xFF2BA6A0))
      ..add(hl('b', 'p0', 20, 'Teal two', m: 0xFF2BA6A0))
      ..add(hl('c', 'p0', 40, 'Plum', m: 0xFF8E3B8E));
    final c = await pump(tester);
    expect(find.widgetWithText(FilterChip, '2'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '1'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '2'));
    await tester.pump();
    expect(
      c.read(canvasUiProvider).filter,
      const ExtractFilter.colour(0xFF2BA6A0),
    );
    expect(find.text('Teal one'), findsOneWidget);
    expect(find.text('Plum'), findsNothing);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('a chip disappears when its last highlight is deleted', (
    tester,
  ) async {
    layer
      ..add(hl('a', 'p0', 1, 'Teal', m: 0xFF2BA6A0))
      ..add(hl('b', 'p0', 20, 'Coral one'));
    await pump(tester);
    expect(find.byType(FilterChip), findsNWidgets(4));
    layer.remove('a');
    await tester.pump();
    expect(find.byType(FilterChip), findsNWidgets(3));
  });

  testWidgets('a filter with nothing to show says so', (tester) async {
    layer.add(hl('a', 'p0', 1, 'A claim'));
    final c = await pump(tester);
    c
        .read(canvasUiProvider.notifier)
        .setFilter(ExtractFilter.colour(Swatch.blue));
    await tester.pump();
    expect(find.text('Nothing marked in this colour yet.'), findsOneWidget);
    expect(find.text('0 items'), findsOneWidget);

    c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.notes);
    await tester.pump();
    expect(find.textContaining('Notes you write'), findsOneWidget);
  });

  testWidgets('follows the document: new, removed and moved pages', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('0 items'), findsOneWidget);
    layer.add(hl('a', 'p1', 1, 'Fresh'));
    await tester.pump();
    expect(find.text('Fresh'), findsOneWidget);
    expect(find.text('p. 2'), findsOneWidget);
    layer.remove('a');
    await tester.pump();
    expect(find.text('Fresh'), findsNothing);
  });

  testWidgets('tapping an item jumps to it', (tester) async {
    layer
      ..add(hl('a', 'p0', 1, 'Alpha'))
      ..add(hl('b', 'p0', 9, 'Beta'));
    await pump(tester);
    await tester.tap(find.text('Beta'));
    expect(jumped, ['b']);
  });

  testWidgets('delete removes the item and offers Undo', (tester) async {
    layer.add(hl('a', 'p0', 1, 'Alpha'));
    await pump(tester);
    await tester.tap(find.byTooltip('Delete highlight'));
    await tester.pump();
    expect(deleted, ['a']);
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Highlight deleted'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500)); // slides in
    await tester.tap(find.text('Undo'));
    expect(undone, 1);
    await tester.pumpAndSettle(const Duration(seconds: 7));
  });

  testWidgets('the delete control is a 48 dp target', (tester) async {
    layer.add(hl('a', 'p0', 1, 'Alpha'));
    await pump(tester);
    final size = tester.getSize(find.byTooltip('Delete highlight'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('a free rectangle shows as an image region', (tester) async {
    layer.add(hl('r', 'p0', -1, '(image region)', m: Swatch.method));
    await pump(tester);
    expect(find.text('Image region'), findsOneWidget);
    expect(find.text('(image region)'), findsNothing);
  });

  testWidgets('a long quote is cut short instead of overflowing', (
    tester,
  ) async {
    layer.add(hl('a', 'p0', 1, List.filled(80, 'lengthy words').join(' ')));
    await pump(tester, width: 280, textScale: 1.3);
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.textContaining('lengthy words'));
    expect(text.maxLines, 6);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('each item is one accessible button with its colour and page', (
    tester,
  ) async {
    layer.add(hl('a', 'p1', 1, 'Spoken quote', m: Swatch.question));
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(find.bySemanticsLabel('Blue, page 2. Spoken quote'), findsOneWidget);
    final node = tester.getSemantics(
      find.bySemanticsLabel('Blue, page 2. Spoken quote'),
    );
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('renders in the dark theme', (tester) async {
    layer.add(hl('a', 'p0', 1, 'Dark quote'));
    await pump(tester, brightness: Brightness.dark);
    expect(find.text('Dark quote'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('notes', () {
    late NotesLayer notes;
    late LinksLayer links;
    late List<String> jumpedNotes, deletedNotes;

    Note nt(String id, String page, double y, String text) =>
        Note(id: id, docId: 'd', pageId: page, x: 0, y: y, text: text);

    setUp(() {
      notes = NotesLayer();
      links = LinksLayer();
      jumpedNotes = [];
      deletedNotes = [];
      source = ExtractController(
        highlights: layer,
        scene: scene,
        notes: notes,
        links: links,
        onJump: (h) => jumped.add(h.id),
        onDelete: (h) {
          deleted.add(h.id);
          layer.remove(h.id);
        },
        onJumpNote: (n) => jumpedNotes.add(n.id),
        onDeleteNote: (n) {
          deletedNotes.add(n.id);
          notes.remove(n.id);
        },
        onUndo: () => undone++,
      );
    });

    Link lk(String id, String note, String hl) =>
        Link(id: id, docId: 'd', fromNoteId: note, toHighlightId: hl);

    testWidgets(
      'the Notes filter lists notes with the quotes they are linked to',
      (tester) async {
        layer.add(hl('h', 'p0', 1, 'The claim itself'));
        notes
          ..add(nt('n', 'p0', 10, 'Why is this true?'))
          ..add(nt('blank', 'p0', 20, '  '));
        links.add(lk('l', 'n', 'h'));
        final c = await pump(tester);
        c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.notes);
        await tester.pump();
        expect(
          find.text('1 item'),
          findsOneWidget,
          reason: 'the blank note is not listed',
        );
        expect(find.text('Why is this true?'), findsOneWidget);
        expect(find.text('↳ “The claim itself”'), findsOneWidget);
        expect(find.text('p. 1'), findsOneWidget);
        expect(
          find.text('The claim itself'),
          findsNothing,
          reason: 'highlights are filtered out',
        );
      },
    );

    testWidgets('All shows each page\'s highlights, then its notes', (
      tester,
    ) async {
      layer
        ..add(hl('h1', 'p0', 1, 'First highlight'))
        ..add(hl('h2', 'p1', 1, 'Second page highlight'));
      notes
        ..add(nt('n1', 'p0', 5, 'Note on one'))
        ..add(nt('n2', 'p1', 5, 'Note on two'));
      await pump(tester);
      expect(find.text('4 items'), findsOneWidget);
      final order = [
        for (final t in tester.widgetList<Text>(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.data == 'First highlight' ||
                    w.data == 'Note on one' ||
                    w.data == 'Second page highlight' ||
                    w.data == 'Note on two'),
          ),
        ))
          t.data,
      ];
      expect(order, [
        'First highlight',
        'Note on one',
        'Second page highlight',
        'Note on two',
      ]);
    });

    testWidgets('a note linked to a deleted highlight lists no quote for it', (
      tester,
    ) async {
      notes.add(nt('n', 'p0', 10, 'Orphaned note'));
      links.add(lk('l', 'n', 'gone'));
      final c = await pump(tester);
      c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.notes);
      await tester.pump();
      expect(find.text('Orphaned note'), findsOneWidget);
      expect(find.textContaining('↳'), findsNothing);
    });

    testWidgets('more than three quotes end with "and N more"', (tester) async {
      notes.add(nt('n', 'p0', 10, 'About many things'));
      for (var i = 0; i < 5; i++) {
        layer.add(hl('h$i', 'p0', i * 10, 'quote number $i'));
        links.add(lk('l$i', 'n', 'h$i'));
      }
      final c = await pump(tester);
      c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.notes);
      await tester.pump();
      expect(find.textContaining('↳'), findsNWidgets(3));
      expect(find.text('and 2 more'), findsOneWidget);
    });

    testWidgets(
      'tapping a note jumps to it; delete removes it and offers Undo',
      (tester) async {
        notes.add(nt('n', 'p0', 10, 'Tap me'));
        final c = await pump(tester);
        c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.notes);
        await tester.pump();
        await tester.tap(find.text('Tap me'));
        expect(jumpedNotes, ['n']);
        await tester.tap(find.byTooltip('Delete note'));
        await tester.pump();
        expect(deletedNotes, ['n']);
        expect(find.text('Note deleted'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Undo'));
        expect(undone, 1);
        await tester.pumpAndSettle(const Duration(seconds: 7));
      },
    );

    testWidgets(
      'a note tile is one accessible button naming what it is about',
      (tester) async {
        layer.add(hl('h', 'p1', 1, 'Spoken source'));
        notes.add(nt('n', 'p1', 10, 'Spoken note'));
        links.add(lk('l', 'n', 'h'));
        final handle = tester.ensureSemantics();
        final c = await pump(tester);
        c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.notes);
        await tester.pump();
        expect(
          find.bySemanticsLabel(
            'Note, page 2. Spoken note. About: Spoken source',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('the note delete control is a 48 dp target', (tester) async {
      notes.add(nt('n', 'p0', 10, 'x'));
      final c = await pump(tester);
      c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.notes);
      await tester.pump();
      final size = tester.getSize(find.byTooltip('Delete note'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('follows the notes layer as notes are typed and removed', (
      tester,
    ) async {
      final c = await pump(tester);
      c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.notes);
      await tester.pump();
      expect(find.textContaining('Notes you write'), findsOneWidget);
      notes.add(nt('n', 'p0', 10, 'Fresh note'));
      await tester.pump();
      expect(find.text('Fresh note'), findsOneWidget);
      notes.remove('n');
      await tester.pump();
      expect(find.text('Fresh note'), findsNothing);
    });

    testWidgets('renders in the dark theme', (tester) async {
      notes.add(nt('n', 'p0', 10, 'Dark note'));
      await pump(tester, brightness: Brightness.dark);
      expect(find.text('Dark note'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
