import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/erase/erase_tool.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:flutter_test/flutter_test.dart';

Ink line(String id, double x0, double y, double x1, {double w = 4}) => Ink(
  id: id,
  docId: 'd',
  samples: Float32List.fromList([x0, y, 0.5, x1, y, 0.5]),
  width: w,
  color: 0xFF000000,
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
  late InkLayer ink;
  late EraserState eraser;
  late FakeEraseSink sink;
  late bool partial;
  late EraseToolController tool;

  setUp(() {
    view = ValueNotifier(const ViewState());
    ink = InkLayer();
    eraser = EraserState();
    sink = FakeEraseSink();
    partial = false;
    tool = EraseToolController(
      view: view,
      ink: ink,
      eraser: eraser,
      partial: () => partial,
      sink: sink,
    );
  });

  group('whole strokes', () {
    test('wiping across a stroke removes it at once, and saves one erase', () {
      ink.add(line('a', 0, 50, 300));
      ink.add(line('keep', 0, 400, 300)); // far away
      tool.start(pt(0, 50));
      expect(ink.byId('a'), isNull, reason: 'gone before the pen lifts');
      tool.move(pt(300, 60));
      expect(sink.commits, isEmpty, reason: 'nothing is written yet');
      tool.end(pt(300, 60));
      expect(ink.byId('keep'), isNotNull);
      final c = sink.commits.single;
      expect(c.deleted, {'a'});
      expect(c.created, isEmpty);
    });

    test('a stroke the eraser does not reach stays', () {
      ink.add(line('a', 0, 50, 300));
      tool.start(pt(0, 100)); // 50 below the line
      tool.end(pt(300, 100));
      expect(ink.byId('a'), isNotNull);
      expect(
        sink.commits,
        isEmpty,
        reason: 'an erase that took nothing is not saved',
      );
    });

    test('a fast sweep cannot jump over a thin line', () {
      ink.add(line('a', 0, 50, 300));
      tool.start(pt(100, -50)); // above the line
      tool.end(pt(100, 120)); // one jump to below it, 170 px away
      expect(ink.byId('a'), isNull);
    });

    test('several strokes in one wipe are one saved erase', () {
      ink.add(line('a', 0, 50, 300));
      ink.add(line('b', 0, 60, 300));
      tool.start(pt(100, 40));
      tool.move(pt(100, 100));
      tool.end(pt(100, 110));
      expect(sink.commits.length, 1);
      expect(sink.commits.single.deleted, {'a', 'b'});
    });
  });

  group('radius', () {
    test('is 14 dp on screen whatever the zoom', () {
      view.value = const ViewState(zoom: 2);
      // The line at world y 50 is screen y 100 at zoom 2.
      ink.add(line('a', 0, 50, 300, w: 0));
      tool.start(pt(0, 100 + 13)); // 13 dp away: touched
      tool.end(pt(10, 113));
      expect(ink.byId('a'), isNull);
      ink.add(line('b', 0, 50, 300, w: 0));
      tool.start(pt(0, 100 + 16)); // 16 dp away: missed
      tool.end(pt(10, 116));
      expect(ink.byId('b'), isNotNull);
    });
  });

  group('partial erase', () {
    setUp(() => partial = true);

    test('cuts the stroke and leaves the rest as new strokes', () {
      ink.add(line('a', 0, 50, 300, w: 0));
      tool.start(pt(150, 50)); // the middle
      tool.end(pt(150, 50));
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
      expect(left.color, 0xFF000000);
      expect(left.width, 0);
    });

    test(
      'a wipe that cuts a piece again leaves no trace of the middle piece',
      () {
        ink.add(line('a', 0, 50, 300, w: 0));
        tool.start(pt(100, 50)); // cuts at 100
        tool.move(pt(200, 50)); // sweeps on, wiping right of the first cut
        tool.end(pt(200, 50));
        final c = sink.commits.single;
        expect(c.deleted, {'a'}, reason: 'only the original was ever stored');
        for (final made in c.created) {
          expect(ink.byId(made.id), isNotNull);
        }
        expect(c.created.length, ink.count);
      },
    );

    test('wiping a stroke out completely leaves nothing', () {
      ink.add(line('a', 140, 50, 160, w: 0));
      tool.start(pt(150, 50));
      tool.end(pt(150, 50));
      expect(ink.count, 0);
      expect(sink.commits.single.created, isEmpty);
      expect(sink.commits.single.deleted, {'a'});
    });
  });

  group('cancel and the ring', () {
    test('cancel puts back everything taken, pieces included', () {
      partial = true;
      ink.add(line('a', 0, 50, 300, w: 0));
      ink.add(line('b', 0, 60, 300, w: 0));
      tool.start(pt(150, 50));
      tool.move(pt(150, 65));
      expect(ink.byId('a'), isNull);
      tool.cancel();
      expect(ink.byId('a'), isNotNull);
      expect(ink.byId('b'), isNotNull);
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
      ink.add(line('a', 0, 50, 300));
      tool.sink = null;
      tool.start(pt(0, 50));
      tool.end(pt(300, 50));
      expect(ink.byId('a'), isNotNull, reason: 'not even shown as gone');
    });
  });
}
