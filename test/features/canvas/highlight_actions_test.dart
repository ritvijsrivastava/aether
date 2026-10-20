import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/marks/highlight_actions.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Log implements HighlightActions {
  final List<String> log = [];
  @override
  void addNote(Highlight h) => log.add('note:${h.id}');
  @override
  void recolor(Highlight h, int color) => log.add('colour:${h.id}:$color');
  @override
  void copyQuote(Highlight h) => log.add('copy:${h.id}');
  @override
  void delete(Highlight h) => log.add('delete:${h.id}');
}

Highlight hl(String id, {List<Box>? rects}) => Highlight(
  id: id,
  docId: 'd',
  pageId: 'p0',
  color: Swatch.amber,
  startChar: 0,
  endChar: 3,
  quote: 'q',
  rects: rects ?? const [Box(50, 50, 250, 62)],
);

const _scene = Scene([
  Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 400, 800)),
]);

void main() {
  late HighlightLayer layer;
  late HighlightFocus focus;
  late Log actions;

  setUp(() {
    layer = HighlightLayer()..add(hl('h'));
    focus = HighlightFocus();
    actions = Log();
  });

  Future<void> pump(
    WidgetTester tester, {
    ViewState view = const ViewState(),
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: Scaffold(
            body: HighlightActionStrip(
              view: ValueNotifier(view),
              scene: ValueNotifier(_scene),
              highlights: layer,
              focus: focus,
              actions: actions,
              viewport: () => size,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('nothing shows until a highlight is in focus', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Add note'), findsNothing);
    focus.show('h');
    await tester.pump();
    expect(find.byTooltip('Add note'), findsOneWidget);
    focus.clear();
    await tester.pump();
    expect(find.byTooltip('Add note'), findsNothing);
  });

  testWidgets('four actions, each a 48 dp target', (tester) async {
    await pump(tester);
    focus.show('h');
    await tester.pump();
    for (final tip in [
      'Add note',
      'Change colour',
      'Copy quote',
      'Delete highlight',
    ]) {
      final r = tester.getRect(find.byTooltip(tip));
      expect(r.width, greaterThanOrEqualTo(48), reason: tip);
      expect(r.height, greaterThanOrEqualTo(48), reason: tip);
    }
  });

  testWidgets('the buttons call their action with the highlight', (
    tester,
  ) async {
    await pump(tester);
    focus.show('h');
    await tester.pump();
    await tester.tap(find.byTooltip('Add note'));
    await tester.tap(find.byTooltip('Copy quote'));
    await tester.tap(find.byTooltip('Delete highlight'));
    expect(actions.log, ['note:h', 'copy:h', 'delete:h']);
  });

  testWidgets('it is a vertical column beside the highlight, to its right', (
    tester,
  ) async {
    await pump(tester);
    focus.show('h');
    await tester.pump();
    final a = tester.getRect(find.byTooltip('Add note'));
    final d = tester.getRect(find.byTooltip('Delete highlight'));
    expect(a.center.dx, d.center.dx, reason: 'one column');
    expect(d.top, greaterThan(a.bottom - 1), reason: 'stacked downwards');
    // The highlight's right edge on screen is 100 + 250 = 350.
    expect(a.left, greaterThan(350));
  });

  testWidgets('with no room on the right it goes to the left', (tester) async {
    layer.add(hl('h', rects: const [Box(50, 50, 390, 62)]));
    await pump(tester, size: const Size(560, 800));
    focus.show('h');
    await tester.pump();
    final a = tester.getRect(find.byTooltip('Add note'));
    expect(a.right, lessThan(150), reason: 'left of the highlight at x=150');
    expect(a.left, greaterThanOrEqualTo(0));
  });

  testWidgets('it stays on screen at the top and bottom edges', (tester) async {
    layer.add(hl('h', rects: const [Box(50, 0, 250, 12)]));
    await pump(tester, view: const ViewState(y: -100));
    focus.show('h');
    await tester.pump();
    expect(
      tester.getRect(find.byTooltip('Add note')).top,
      greaterThanOrEqualTo(0),
    );
    layer.add(hl('h', rects: const [Box(50, 780, 250, 792)]));
    await tester.pump();
    expect(
      tester.getRect(find.byTooltip('Delete highlight')).bottom,
      lessThanOrEqualTo(800),
    );
  });

  testWidgets('Change colour swaps in the colours; picking one recolours', (
    tester,
  ) async {
    await pump(tester);
    focus.show('h');
    await tester.pump();
    await tester.tap(find.byTooltip('Change colour'));
    await tester.pump();
    expect(find.byTooltip('Add note'), findsNothing);
    expect(find.byTooltip('Blue'), findsOneWidget);
    await tester.tap(find.byTooltip('Blue'));
    await tester.pump();
    expect(actions.log, ['colour:h:${Swatch.blue}']);
    expect(
      find.byTooltip('Add note'),
      findsOneWidget,
      reason: 'back to actions',
    );
  });

  testWidgets('Back leaves the colours without changing anything', (
    tester,
  ) async {
    await pump(tester);
    focus.show('h');
    await tester.pump();
    await tester.tap(find.byTooltip('Change colour'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(actions.log, isEmpty);
    expect(find.byTooltip('Add note'), findsOneWidget);
  });

  testWidgets('a different highlight starts on the actions, not the colours', (
    tester,
  ) async {
    layer.add(hl('g', rects: const [Box(50, 200, 250, 212)]));
    await pump(tester);
    focus.show('h');
    await tester.pump();
    await tester.tap(find.byTooltip('Change colour'));
    await tester.pump();
    focus.show('g');
    await tester.pump();
    expect(find.byTooltip('Add note'), findsOneWidget);
  });

  testWidgets('it goes when its highlight is deleted', (tester) async {
    await pump(tester);
    focus.show('h');
    await tester.pump();
    layer.remove('h');
    await tester.pump();
    expect(find.byTooltip('Add note'), findsNothing);
  });

  testWidgets('it follows the view when the canvas pans', (tester) async {
    final view = ValueNotifier(const ViewState());
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: Scaffold(
            body: HighlightActionStrip(
              view: view,
              scene: ValueNotifier(_scene),
              highlights: layer,
              focus: focus,
              actions: actions,
              viewport: () => const Size(1000, 800),
            ),
          ),
        ),
      ),
    );
    focus.show('h');
    await tester.pump();
    final before = tester.getRect(find.byTooltip('Add note')).left;
    view.value = const ViewState(x: 50);
    await tester.pump();
    expect(tester.getRect(find.byTooltip('Add note')).left, before + 50);
  });

  test('the owner can re-show the same highlight without a notification', () {
    var n = 0;
    focus.addListener(() => n++);
    focus.show('h');
    focus.show('h');
    expect(n, 1);
    focus.clear();
    focus.clear();
    expect(n, 2);
  });

  testWidgets('the current colour is the one the strip marks', (tester) async {
    await pump(tester);
    focus.show('h');
    await tester.pump();
    await tester.tap(find.byTooltip('Change colour'));
    await tester.pump();
    final c = ProviderScope.containerOf(tester.element(find.byTooltip('Blue')));
    expect(c.read(canvasUiProvider).markColor, Swatch.coral);
  });
}
