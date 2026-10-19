import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
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
  Meaning m = Meaning.claim,
}) => Highlight(
  id: id,
  docId: 'd',
  pageId: page,
  meaning: m,
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

  testWidgets('lists highlights in reading order with meaning and page', (
    tester,
  ) async {
    layer
      ..add(hl('c', 'p1', 5, 'Third quote', m: Meaning.question))
      ..add(hl('a', 'p0', 90, 'Second quote', m: Meaning.method))
      ..add(hl('b', 'p0', 10, 'First quote'));
    await pump(tester);
    expect(find.text('3 items'), findsOneWidget);
    final order = [
      for (final t in tester.widgetList<Text>(find.textContaining(' quote')))
        t.data,
    ];
    expect(order, ['First quote', 'Second quote', 'Third quote']);
    expect(find.text('Claim'), findsWidgets); // the chip and the item
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
      ..add(hl('b', 'p0', 20, 'A method', m: Meaning.method))
      ..add(hl('c', 'p0', 40, 'A question', m: Meaning.question));
    final c = await pump(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Method'));
    await tester.pump();
    expect(c.read(canvasUiProvider).filter, ExtractFilter.method);
    expect(find.text('A method'), findsOneWidget);
    expect(find.text('A claim'), findsNothing);
    expect(find.text('1 item'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await tester.pump();
    expect(find.text('3 items'), findsOneWidget);
  });

  testWidgets('a filter with nothing to show says so', (tester) async {
    layer.add(hl('a', 'p0', 1, 'A claim'));
    final c = await pump(tester);
    c.read(canvasUiProvider.notifier).setFilter(ExtractFilter.question);
    await tester.pump();
    expect(find.text('Nothing marked as Question yet.'), findsOneWidget);
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
    layer.add(hl('r', 'p0', -1, '(image region)', m: Meaning.method));
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

  testWidgets('each item is one accessible button with its meaning and page', (
    tester,
  ) async {
    layer.add(hl('a', 'p1', 1, 'Spoken quote', m: Meaning.question));
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(
      find.bySemanticsLabel('Question, page 2. Spoken quote'),
      findsOneWidget,
    );
    final node = tester.getSemantics(
      find.bySemanticsLabel('Question, page 2. Spoken quote'),
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
}
