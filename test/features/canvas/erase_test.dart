import 'dart:ui';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/erase/erase_tool.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Ink line(
  String id,
  String? page,
  double x0,
  double y,
  double x1, {
  double w = 4,
}) => Ink(
  id: id,
  docId: 'd',
  pageId: page,
  samples: Float32List.fromList([x0, y, 0.5, x1, y, 0.5]),
  width: w,
  color: 0xFF000000,
);

Highlight hl(String id, String page, Box r) => Highlight(
  id: id,
  docId: 'd',
  pageId: page,
  meaning: Meaning.claim,
  startChar: 0,
  endChar: 3,
  quote: 'q',
  rects: [r],
);

class FakeEraseSink implements EraseSink {
  final List<({Set<String> deleted, List<Ink> created})> commits = [];
  int _n = 0;
  @override
  String newId() => 'piece${++_n}';
  @override
  void commitErase({
    required Set<String> deleted,
    required List<Ink> created,
  }) => commits.add((deleted: deleted, created: created));
}

ToolPoint pt(double x, double y) => ToolPoint(
  position: Offset(x, y),
  time: Duration.zero,
  kind: PointerDeviceKind.stylus,
);

void main() {
  late ValueNotifier<ViewState> view;
  late ValueNotifier<Scene> scene;
  late InkLayer ink;
  late HighlightLayer highlights;
  late EraserState eraser;
  late FakeEraseSink sink;
  late bool partial;
  late EraseToolController tool;

  setUp(() {
    view = ValueNotifier(const ViewState());
    scene = ValueNotifier(
      const Scene([
        Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 600, 800)),
        Card(id: 'p1', index: 1, rect: Rect.fromLTWH(100, 980, 600, 800)),
      ]),
    );
    ink = InkLayer();
    highlights = HighlightLayer();
    eraser = EraserState();
    sink = FakeEraseSink();
    partial = false;
    tool = EraseToolController(
      view: view,
      scene: scene,
      ink: ink,
      highlights: highlights,
      eraser: eraser,
      partial: () => partial,
      sink: sink,
    );
  });

  // Page p0's origin is world (100, 100): page (50, 50) is screen (150, 150).
  group('whole strokes', () {
    test('wiping across a stroke removes it at once, and saves one erase', () {
      ink.add(line('a', 'p0', 0, 50, 300)); // world y = 150
      ink.add(line('keep', 'p0', 0, 400, 300)); // far away
      tool.start(pt(100, 140));
      expect(ink.byId('a'), isNull, reason: 'gone before the pen lifts');
      tool.move(pt(300, 160));
      expect(sink.commits, isEmpty, reason: 'nothing is written yet');
      tool.end(pt(300, 160));
      expect(ink.byId('keep'), isNotNull);
      final c = sink.commits.single;
      expect(c.deleted, {'a'});
      expect(c.created, isEmpty);
    });

    test('a stroke the eraser does not reach stays', () {
      ink.add(line('a', 'p0', 0, 50, 300));
      tool.start(pt(100, 200)); // 50 below the line
      tool.end(pt(300, 200));
      expect(ink.byId('a'), isNotNull);
      expect(
        sink.commits,
        isEmpty,
        reason: 'an erase that took nothing is not saved',
      );
    });

    test('takes highlights it touches too', () {
      highlights.add(hl('h', 'p0', const Box(40, 40, 200, 52)));
      highlights.add(hl('far', 'p0', const Box(40, 500, 200, 512)));
      tool.start(pt(200, 146)); // page (100, 46): 6 above the rect's top
      tool.end(pt(220, 146));
      expect(highlights.byId('h'), isNull);
      expect(highlights.byId('far'), isNotNull);
      expect(sink.commits.single.deleted, {'h'});
    });

    test('a fast sweep cannot jump over a thin line', () {
      ink.add(line('a', 'p0', 0, 50, 300));
      tool.start(pt(200, 100)); // above the line
      tool.end(pt(200, 220)); // one jump to below it, 120 px away
      expect(ink.byId('a'), isNull);
    });

    test('ink that runs past the page edge is found from outside the page', () {
      ink.add(
        line('a', 'p0', 550, 50, 800),
      ); // reaches page x = 800 (page is 600)
      tool.start(pt(850, 150)); // world x 850: page x 750, past the page
      tool.end(pt(860, 150));
      expect(ink.byId('a'), isNull);
    });

    test('erases canvas-space ink that belongs to no page', () {
      ink.add(line('free', null, 10, 20, 90));
      tool.start(pt(50, 20));
      tool.end(pt(60, 20));
      expect(ink.byId('free'), isNull);
      expect(sink.commits.single.deleted, {'free'});
    });

    test('works on the second page', () {
      ink.add(line('b', 'p1', 0, 50, 300)); // world y 1030
      tool.start(pt(200, 1030));
      tool.end(pt(210, 1030));
      expect(ink.byId('b'), isNull);
    });

    test('several marks in one wipe are one saved erase', () {
      ink.add(line('a', 'p0', 0, 50, 300));
      ink.add(line('b', 'p0', 0, 60, 300));
      highlights.add(hl('h', 'p0', const Box(0, 70, 300, 80)));
      tool.start(pt(200, 140));
      tool.move(pt(200, 200));
      tool.end(pt(200, 210));
      expect(sink.commits.length, 1);
      expect(sink.commits.single.deleted, {'a', 'b', 'h'});
    });
  });

  group('radius', () {
    test('is 14 dp on screen: 7 page points when zoomed in to 200%', () {
      view.value = const ViewState(zoom: 2);
      // Line at world y 150 is screen y 300 at zoom 2.
      ink.add(line('a', 'p0', 0, 50, 300, w: 0));
      tool.start(pt(300, 300 + 13)); // 13 dp away: touched
      tool.end(pt(310, 313));
      expect(ink.byId('a'), isNull);
      ink.add(line('b', 'p0', 0, 50, 300, w: 0));
      tool.start(pt(300, 300 + 16)); // 16 dp away: missed
      tool.end(pt(310, 316));
      expect(ink.byId('b'), isNotNull);
    });
  });

  group('partial erase', () {
    setUp(() => partial = true);

    test('cuts the stroke and leaves the rest as new strokes', () {
      ink.add(line('a', 'p0', 0, 50, 300, w: 0));
      tool.start(pt(250, 150)); // page x 150, the middle
      tool.end(pt(250, 150));
      expect(ink.byId('a'), isNull);
      final c = sink.commits.single;
      expect(c.deleted, {'a'});
      expect(c.created.length, 2);
      expect(ink.count, 2);
      final left = c.created.firstWhere((i) => i.samples[0] == 0);
      expect(
        left.samples[left.samples.length - 3],
        closeTo(136, 1e-3),
      ); // 150 - 14
      expect(left.pageId, 'p0');
      expect(left.color, 0xFF000000);
      expect(left.width, 0);
    });

    test(
      'a wipe that cuts a piece again leaves no trace of the middle piece',
      () {
        ink.add(line('a', 'p0', 0, 50, 300, w: 0));
        tool.start(pt(200, 150)); // cuts at page 100
        tool.move(
          pt(300, 150),
        ); // sweeps on, wiping what is right of the first cut
        tool.end(pt(300, 150));
        final c = sink.commits.single;
        expect(c.deleted, {'a'}, reason: 'only the original was ever stored');
        for (final made in c.created) {
          expect(
            ink.byId(made.id),
            isNotNull,
            reason: 'what is saved is on the page',
          );
        }
        expect(c.created.length, ink.count);
      },
    );

    test('wiping a stroke out completely leaves nothing', () {
      ink.add(line('a', 'p0', 140, 50, 160, w: 0));
      tool.start(pt(250, 150));
      tool.end(pt(250, 150));
      expect(ink.count, 0);
      expect(sink.commits.single.created, isEmpty);
      expect(sink.commits.single.deleted, {'a'});
    });

    test('still takes a whole highlight', () {
      highlights.add(hl('h', 'p0', const Box(100, 40, 200, 52)));
      tool.start(pt(250, 146));
      tool.end(pt(250, 146));
      expect(highlights.byId('h'), isNull);
    });
  });

  group('cancel and the ring', () {
    test('cancel puts back everything taken, pieces included', () {
      partial = true;
      ink.add(line('a', 'p0', 0, 50, 300, w: 0));
      ink.add(line('b', 'p0', 0, 60, 300, w: 0));
      highlights.add(hl('h', 'p0', const Box(0, 40, 300, 52)));
      tool.start(pt(250, 150));
      tool.move(pt(250, 165));
      expect(ink.byId('a'), isNull);
      tool.cancel();
      expect(ink.byId('a'), isNotNull);
      expect(ink.byId('b'), isNotNull);
      expect(highlights.byId('h'), isNotNull);
      expect(ink.count, 2, reason: 'the cut pieces are gone again');
      expect(sink.commits, isEmpty);
      expect(tool.isActive, isFalse);
    });

    test('the ring follows the pen and goes away', () {
      expect(eraser.center, isNull);
      tool.start(pt(150, 150));
      expect(eraser.center, const Offset(150, 150));
      tool.move(pt(170, 160));
      expect(eraser.center, const Offset(170, 160));
      tool.end(pt(170, 160));
      expect(eraser.center, isNull);
      tool.start(pt(1, 1));
      tool.cancel();
      expect(eraser.center, isNull);
    });

    test('without a sink the tool does nothing', () {
      ink.add(line('a', 'p0', 0, 50, 300));
      tool.sink = null;
      tool.start(pt(150, 150));
      tool.end(pt(160, 150));
      expect(ink.byId('a'), isNotNull);
    });

    test('a stray move or end after a cancel is ignored', () {
      ink.add(line('a', 'p0', 0, 50, 300));
      tool.start(pt(500, 500));
      tool.cancel();
      tool.move(pt(150, 150));
      tool.end(pt(150, 150));
      expect(ink.byId('a'), isNotNull);
      expect(sink.commits, isEmpty);
    });
  });

  testWidgets('the eraser ring paints a circle at the pen', (tester) async {
    await tester.runAsync(() async {
      eraser.show(const Offset(50, 50));
      final rec = PictureRecorder();
      EraserPainter(
        eraser: eraser,
        tokens: AetherTokens.light,
      ).paint(Canvas(rec), const Size(100, 100));
      final img = await rec.endRecording().toImage(100, 100);
      final d = (await img.toByteData())!;
      int a(int x, int y) => d.getUint8((y * 100 + x) * 4 + 3);
      expect(a(50, 36), greaterThan(100), reason: 'on the ring, 14 px above');
      expect(a(50, 50), inInclusiveRange(1, 60), reason: 'a faint fill inside');
      expect(a(5, 5), 0);
    });
  });
}
