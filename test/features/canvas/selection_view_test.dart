import 'dart:ui';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
import 'package:aether/features/canvas/notes/notes_layer.dart';
import 'package:aether/features/canvas/select/select_tool.dart';
import 'package:aether/features/canvas/select/selection.dart';
import 'package:aether/features/canvas/select/selection_view.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card, Ink;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeActions implements SelectionActions {
  final List<String> log = [];
  @override
  void recolorHighlight(int argb) => log.add('highlight:$argb');
  @override
  void recolorInk(int argb) => log.add('ink:$argb');
  @override
  void deleteSelection() => log.add('delete');
  @override
  void bringForward() => log.add('forward');
  @override
  void sendBack() => log.add('back');
}

Ink line(String id) => Ink(
  id: id,
  docId: 'd',
  pageId: 'p0',
  samples: Float32List.fromList([50, 300, 0.5, 250, 300, 0.5]),
  width: 4,
  color: 1,
);

Highlight hl(String id) => Highlight(
  id: id,
  docId: 'd',
  pageId: 'p0',
  color: Swatch.claim,
  startChar: 0,
  endChar: 3,
  quote: 'q',
  rects: const [Box(50, 50, 250, 62)],
);

const _scene = Scene([
  Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 600, 800)),
]);

void main() {
  late InkLayer ink;
  late HighlightLayer highlights;
  late NotesLayer notes;
  late SelectionState selection;
  late FakeActions actions;

  setUp(() {
    ink = InkLayer()..add(line('i'));
    highlights = HighlightLayer()..add(hl('h'));
    notes = NotesLayer();
    selection = SelectionState();
    actions = FakeActions();
  });

  Future<void> pump(
    WidgetTester tester, {
    ViewState view = const ViewState(),
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: Scaffold(
            body: MarkSelectionOverlay(
              view: ValueNotifier(view),
              scene: ValueNotifier(_scene),
              selection: selection,
              ink: ink,
              highlights: highlights,
              notes: notes,
              actions: actions,
              viewport: () => const Size(1000, 800),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('nothing is shown with nothing selected', (tester) async {
    await pump(tester);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('a selection shows its count, Recolor and Delete', (
    tester,
  ) async {
    await pump(tester);
    selection.set([
      const MarkRef(MarkKind.ink, 'i'),
      const MarkRef(MarkKind.highlight, 'h'),
    ]);
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Recolor'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    expect(actions.log, ['delete']);
  });

  testWidgets(
    'Recolor offers the marker colours for highlights and the pen colours for ink',
    (tester) async {
      await pump(tester);
      selection.set([
        const MarkRef(MarkKind.ink, 'i'),
        const MarkRef(MarkKind.highlight, 'h'),
      ]);
      await tester.pump();
      await tester.tap(find.text('Recolor'));
      await tester.pump();
      // Marker colours first (Coral, Amber, Blue), then the pen's (Black, ...).
      expect(find.byTooltip('Amber'), findsNWidgets(2));
      expect(find.byTooltip('Black'), findsOneWidget);
      await tester.tap(find.byTooltip('Amber').first);
      await tester.tap(find.byTooltip('Blue').last);
      expect(actions.log, ['highlight:${Swatch.amber}', 'ink:${Swatch.blue}']);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
    },
  );

  testWidgets(
    'only ink shows the pen colours; only highlights the marker colours',
    (tester) async {
      await pump(tester);
      selection.set([const MarkRef(MarkKind.ink, 'i')]);
      await tester.pump();
      await tester.tap(find.text('Recolor'));
      await tester.pump();
      expect(find.byTooltip('Black'), findsOneWidget);
      expect(find.byTooltip('Coral'), findsOneWidget);
      selection.set([const MarkRef(MarkKind.highlight, 'h')]);
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.tap(find.text('Recolor'));
      await tester.pump();
      expect(find.byTooltip('Amber'), findsOneWidget);
      expect(find.byTooltip('Black'), findsNothing);
    },
  );

  testWidgets('a selected note can go forward or back', (tester) async {
    notes.add(
      const Note(id: 'n', docId: 'd', pageId: 'p0', x: 5, y: 5, text: 'x'),
    );
    await pump(tester);
    selection.set([const MarkRef(MarkKind.note, 'n')]);
    await tester.pump();
    await tester.tap(find.text('Forward'));
    await tester.tap(find.text('Back'));
    expect(actions.log, ['forward', 'back']);
    expect(find.byTooltip('Bring forward'), findsOneWidget);
    expect(find.byTooltip('Send back'), findsOneWidget);
    for (final label in ['Forward', 'Back', 'Delete']) {
      final r = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
      );
      expect(r.height, greaterThanOrEqualTo(48), reason: label);
    }
  });

  testWidgets('ink and highlights have no order buttons', (tester) async {
    await pump(tester);
    selection.set([
      const MarkRef(MarkKind.ink, 'i'),
      const MarkRef(MarkKind.highlight, 'h'),
    ]);
    await tester.pump();
    expect(find.text('Forward'), findsNothing);
    expect(find.text('Back'), findsNothing);
  });

  testWidgets('a note alone has Delete but no Recolor', (tester) async {
    notes.add(
      const Note(id: 'n', docId: 'd', pageId: 'p0', x: 5, y: 5, text: 'x'),
    );
    await pump(tester);
    selection.set([const MarkRef(MarkKind.note, 'n')]);
    await tester.pump();
    expect(find.text('Recolor'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the buttons are 48 dp tall and the pill stays on screen', (
    tester,
  ) async {
    await pump(tester, view: const ViewState(x: -5000, y: -5000));
    selection.set([const MarkRef(MarkKind.ink, 'i')]);
    await tester.pump();
    final r = tester.getRect(
      find
          .descendant(
            of: find.byType(MarkSelectionOverlay),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(r.height, greaterThanOrEqualTo(48));
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(1000));
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(800));
  });

  testWidgets('goes away when the selection is cleared or its marks are gone', (
    tester,
  ) async {
    await pump(tester);
    selection.set([const MarkRef(MarkKind.ink, 'i')]);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    ink.remove('i');
    await tester.pump();
    expect(find.text('1 selected'), findsNothing, reason: 'its box is gone');
  });

  testWidgets(
    'the outline is dashed indigo round the selection; the loop shows too',
    (tester) async {
      await tester.runAsync(() async {
        final lasso = LiveLasso();
        selection.set([const MarkRef(MarkKind.ink, 'i')]);
        final rec = PictureRecorder();
        SelectionPainter(
          view: ValueNotifier(const ViewState()),
          scene: ValueNotifier(_scene),
          selection: selection,
          lasso: lasso,
          ink: ink,
          highlights: highlights,
          notes: notes,
          tokens: AetherTokens.light,
        ).paint(Canvas(rec), const Size(800, 800));
        final img = await rec.endRecording().toImage(800, 800);
        final d = (await img.toByteData())!;
        int a(int x, int y) => d.getUint8((y * 800 + x) * 4 + 3);
        // The ink is at world y 400 from x 150..350; its box is inflated 2 + 6.
        var onTop = 0;
        for (var x = 140; x < 360; x++) {
          if (a(x, 392) > 100) onTop++;
        }
        expect(onTop, greaterThan(30), reason: 'dashes along the top edge');
        expect(onTop, lessThan(200), reason: 'but not a solid line');
        expect(a(250, 500), 0, reason: 'nothing away from it');
        expect(
          a(250, 400),
          inInclusiveRange(1, 40),
          reason: 'a faint wash inside',
        );
      });
    },
  );
}
