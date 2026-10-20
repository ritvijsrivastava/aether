import 'dart:ui';

import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:aether/features/canvas/select/select_tool.dart';
import 'package:aether/features/canvas/select/selection.dart';
import 'package:aether/features/canvas/select/selection_view.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Ink;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeActions implements SelectionActions {
  final List<String> log = [];
  @override
  void recolorInk(int argb) => log.add('ink:$argb');
  @override
  void deleteSelection() => log.add('delete');
}

Ink line(String id) => Ink(
  id: id,
  docId: 'd',
  samples: Float32List.fromList([50, 300, 0.5, 250, 300, 0.5]),
  width: 4,
  color: 1,
);

void main() {
  late InkLayer ink;
  late SelectionState selection;
  late FakeActions actions;

  setUp(() {
    ink = InkLayer()..add(line('i'));
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
              selection: selection,
              ink: ink,
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
    selection.set([const MarkRef(MarkKind.ink, 'i')]);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Recolor'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    expect(actions.log, ['delete']);
  });

  testWidgets('Recolor offers the pen colours and picking one acts', (
    tester,
  ) async {
    await pump(tester);
    selection.set([const MarkRef(MarkKind.ink, 'i')]);
    await tester.pump();
    await tester.tap(find.text('Recolor'));
    await tester.pump();
    expect(find.byTooltip('Colour'), findsNWidgets(4));
    await tester.tap(find.byTooltip('Colour').at(1));
    expect(actions.log, ['ink:${Swatch.coral}']);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
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
          selection: selection,
          lasso: lasso,
          ink: ink,
          tokens: AetherTokens.light,
        ).paint(Canvas(rec), const Size(800, 800));
        final img = await rec.endRecording().toImage(800, 800);
        final d = (await img.toByteData())!;
        int a(int x, int y) => d.getUint8((y * 800 + x) * 4 + 3);
        // The ink is at world y 300 from x 50..250; its box is inflated 2 + 6.
        var onTop = 0;
        for (var x = 40; x < 260; x++) {
          if (a(x, 292) > 100) onTop++;
        }
        expect(onTop, greaterThan(30), reason: 'dashes along the top edge');
        expect(onTop, lessThan(200), reason: 'but not a solid line');
        expect(a(250, 400), 0, reason: 'nothing away from it');
        expect(
          a(150, 300),
          inInclusiveRange(1, 40),
          reason: 'a faint wash inside',
        );
      });
    },
  );
}
