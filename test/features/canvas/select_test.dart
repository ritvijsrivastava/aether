import 'dart:ui';

import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:aether/features/canvas/select/ink_hit.dart';
import 'package:aether/features/canvas/select/select_tool.dart';
import 'package:aether/features/canvas/select/selection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Ink line(String id, double x0, double y, double x1) => Ink(
  id: id,
  docId: 'd',
  samples: Float32List.fromList([x0, y, 0.5, x1, y, 0.5]),
  width: 4,
  color: 0xFF000000,
);

ToolPoint pt(double x, double y) => ToolPoint(
  position: Offset(x, y),
  time: Duration.zero,
  kind: PointerDeviceKind.stylus,
);

class FakeSelectSink implements SelectSink {
  final List<List<Mark>> moves = [];
  final List<({Set<String> deleted, List<Ink> created})> cuts = [];
  int _n = 0;
  @override
  void commitMove(List<Mark> finals) => moves.add(finals);
  @override
  String newId() => 'piece${++_n}';
  @override
  void commitCut({required Set<String> deleted, required List<Ink> created}) =>
      cuts.add((deleted: deleted, created: created));
}

void main() {
  late InkLayer ink;
  late InkHitTester hit;

  setUp(() {
    ink = InkLayer();
    hit = InkHitTester(ink: ink);
  });

  group('SelectionState', () {
    test('sets, compares, prunes and groups by kind', () {
      final s = SelectionState();
      var n = 0;
      s.addListener(() => n++);
      s.set([const MarkRef(MarkKind.ink, 'a')]);
      s.set([const MarkRef(MarkKind.ink, 'a')]);
      expect(n, 1, reason: 'the same set again is not a change');
      expect(s.count, 1);
      expect(s.idsOf(MarkKind.ink), ['a']);
      s.prune((r) => false);
      expect(s.isEmpty, isTrue);
      expect(n, 2);
      s.clear();
      s.clear();
      expect(n, 2, reason: 'clearing an empty selection is no change');
    });
  });

  group('InkHitTester.markAt', () {
    test('a stroke is found under a point near it', () {
      ink.add(line('i', 50, 56, 300));
      expect(hit.markAt(const Offset(250, 56), 1)!.kind, MarkKind.ink);
    });

    test('nothing is found on bare canvas', () {
      ink.add(line('i', 50, 56, 300));
      expect(hit.markAt(const Offset(650, 700), 1), isNull);
    });

    test('ink is within 10 dp at any zoom', () {
      ink.add(line('i', 50, 56, 300));
      expect(hit.markAt(const Offset(250, 56 + 15), 1), isNull);
      expect(
        hit.markAt(const Offset(250, 56 + 15), 0.5),
        isNotNull,
        reason: 'zoomed out, 15 world units is 7.5 dp',
      );
    });
  });

  group('lasso and marquee', () {
    setUp(() {
      ink.add(line('i', 50, 300, 250)); // y 300
      ink.add(line('far', 50, 700, 250)); // y 700
    });

    test('a stroke wholly inside is picked whole', () {
      final r = hit.cutLoop(const [
        Offset(40, 280),
        Offset(260, 280),
        Offset(260, 320),
        Offset(40, 320),
      ]);
      expect({for (final m in r.whole) m.id}, {'i'});
      expect(r.cuts, isEmpty);
    });

    test('a stroke the edge runs through is cut there', () {
      // A loop over the left half of the stroke (x 50..250 at y 300).
      final r = hit.cutLoop(const [
        Offset(20, 280),
        Offset(150, 280),
        Offset(150, 320),
        Offset(20, 320),
      ]);
      expect(r.whole, isEmpty);
      final c = r.cuts.single;
      expect(c.original.id, 'i');
      final inn = c.inside.single, out = c.outside.single;
      expect(inn[0], 50);
      expect(
        inn[inn.length - 3],
        closeTo(150, 0.01),
        reason: 'cut on the edge',
      );
      expect(out[0], closeTo(150, 0.01));
      expect(out[out.length - 3], 250);
    });

    test('strokes the region misses are left alone', () {
      final r = hit.cutRect(const Rect.fromLTRB(0, 0, 30, 30));
      expect(r.isEmpty, isTrue);
    });

    test('a rectangle cuts the same way', () {
      final r = hit.cutRect(const Rect.fromLTRB(100, 280, 400, 320));
      expect(r.cuts.single.inside.single[0], closeTo(100, 0.01));
    });

    test('a stroke that leaves and comes back gives two inside pieces', () {
      ink.replaceAll([
        Ink(
          id: 'u',
          docId: 'd',
          samples: Float32List.fromList([
            0, 50, 0.5, 100, 50, 0.5, 100, 150, 0.5, 0, 150, 0.5, //
          ]),
          width: 2,
          color: 1,
        ),
      ]);
      final r = hit.cutRect(const Rect.fromLTRB(-10, 0, 50, 200));
      final c = r.cuts.single;
      expect(c.inside.length, 2);
      expect(c.outside.length, 1);
    });

    test('the box round a selection covers every stroke in world space', () {
      ink.add(line('j', 500, 600, 520));
      final b = hit.unionBounds([
        const MarkRef(MarkKind.ink, 'i'),
        const MarkRef(MarkKind.ink, 'j'),
      ])!;
      expect(
        b.left,
        closeTo(48, 1e-6),
        reason: "the stroke's own width pads its bounds",
      );
      expect(b.right, closeTo(522, 1e-6));
      expect(b.top, closeTo(298, 1e-6));
      expect(b.bottom, closeTo(602, 1e-6));
    });

    test('strokes that are gone have no box', () {
      expect(hit.boundsOf(const MarkRef(MarkKind.ink, 'nope')), isNull);
      expect(hit.unionBounds([const MarkRef(MarkKind.ink, 'nope')]), isNull);
    });
  });

  group('SelectToolController', () {
    late ValueNotifier<ViewState> view;
    late SelectionState selection;
    late LiveLasso lasso;
    late FakeSelectSink sink;
    late bool shift;
    late SelectToolController tool;

    setUp(() {
      view = ValueNotifier(const ViewState());
      selection = SelectionState();
      lasso = LiveLasso();
      sink = FakeSelectSink();
      shift = false;
      tool = SelectToolController(
        view: view,
        selection: selection,
        live: lasso,
        ink: ink,
        shift: () => shift,
        sink: sink,
      );
      ink.add(line('i', 50, 300, 250));
      ink.add(line('j', 500, 600, 520));
    });

    test('a tap selects the stroke under it; a tap on bare canvas clears', () {
      tool.start(pt(250, 300));
      tool.end(pt(250, 300));
      expect(selection.refs, {const MarkRef(MarkKind.ink, 'i')});
      tool.start(pt(660, 300));
      tool.end(pt(660, 300));
      expect(selection.isEmpty, isTrue);
    });

    test('drawing a loop selects what it encloses and shows the loop', () {
      tool.start(pt(40, 280));
      tool.move(pt(40, 320));
      expect(lasso.active, isTrue);
      tool.move(pt(260, 320));
      tool.move(pt(260, 280));
      tool.end(pt(50, 280));
      expect(selection.refs, {const MarkRef(MarkKind.ink, 'i')});
      expect(lasso.active, isFalse);
    });

    test('Shift draws a rectangle', () {
      shift = true;
      tool.start(pt(490, 590));
      tool.move(pt(500, 600));
      expect(lasso.marquee, isTrue);
      tool.move(pt(520, 610));
      tool.end(pt(520, 610));
      expect(selection.refs, {const MarkRef(MarkKind.ink, 'j')});
    });

    test('a new loop replaces the old selection', () {
      selection.set([const MarkRef(MarkKind.ink, 'j')]);
      tool.start(pt(40, 280));
      tool.move(pt(40, 320));
      tool.move(pt(260, 320));
      tool.move(pt(260, 280));
      tool.end(pt(50, 280));
      expect(selection.refs.single.id, 'i');
    });

    test('a loop over part of a stroke selects just that part', () {
      // The loop covers the left half of stroke i (x 50..250 at y 300).
      tool.start(pt(20, 280));
      tool.move(pt(20, 320));
      tool.move(pt(150, 320));
      tool.move(pt(150, 280));
      tool.end(pt(22, 280));
      final cut = sink.cuts.single;
      expect(cut.deleted, {'i'});
      expect(ink.byId('i'), isNull, reason: 'the original is replaced');
      expect(cut.created.length, 2, reason: 'one piece inside, one outside');
      final sel = selection.refs.single;
      final inside = ink.byId(sel.id)!;
      expect(inside.bounds.x1, lessThan(160), reason: 'the picked part');
      expect(ink.count, 3, reason: 'two pieces and the untouched j');
    });

    test('the cut-out part moves, the rest stays', () {
      tool.start(pt(20, 280));
      tool.move(pt(20, 320));
      tool.move(pt(150, 320));
      tool.move(pt(150, 280));
      tool.end(pt(22, 280));
      final pickedId = selection.refs.single.id;
      final outsideId = [
        for (final s in ink.all)
          if (s.id != pickedId && s.id != 'j') s.id,
      ].single;
      final outsideBefore = ink.byId(outsideId)!.samples.toList();
      tool.start(pt(100, 300)); // inside the selection's outline
      tool.move(pt(100, 360));
      tool.end(pt(100, 360));
      expect(ink.byId(pickedId)!.bounds.y0, greaterThan(350));
      expect(ink.byId(outsideId)!.samples.toList(), outsideBefore);
      expect(sink.moves.single.single.id, pickedId);
    });

    test('a stroke wholly inside the loop is not cut', () {
      tool.start(pt(40, 280));
      tool.move(pt(40, 320));
      tool.move(pt(260, 320));
      tool.move(pt(260, 280));
      tool.end(pt(42, 280));
      expect(sink.cuts, isEmpty);
      expect(selection.refs.single.id, 'i');
    });

    group('moving', () {
      setUp(() {
        selection.set([
          const MarkRef(MarkKind.ink, 'i'),
          const MarkRef(MarkKind.ink, 'j'),
        ]);
      });

      test('dragging the selection moves the strokes', () {
        tool.start(pt(250, 300)); // inside the selection's outline
        tool.move(pt(290, 330));
        expect(ink.byId('i')!.samples[0], 90, reason: 'live, as it is dragged');
        tool.end(pt(290, 330));
        final done = sink.moves.single;
        expect({for (final m in done) m.id}, {'i', 'j'});
        expect(ink.byId('i')!.samples[1], 330);
      });

      test('an ink point keeps its pressure when moved', () {
        tool.start(pt(250, 300));
        tool.move(pt(290, 330));
        tool.end(pt(290, 330));
        expect(ink.byId('i')!.samples[2], 0.5);
      });

      test('a drag that goes nowhere saves nothing', () {
        tool.start(pt(250, 300));
        tool.move(pt(290, 330));
        tool.move(pt(250, 300));
        tool.end(pt(250, 300));
        expect(sink.moves, isEmpty);
      });

      test('cancel puts everything back', () {
        tool.start(pt(250, 300));
        tool.move(pt(310, 360));
        tool.cancel();
        expect(ink.byId('i')!.samples[0], 50);
        expect(sink.moves, isEmpty);
      });

      test('the zoom and pan do not change what a move means', () {
        view.value = const ViewState(x: 20, y: 10, zoom: 2);
        // Ink world (150, 300) is screen (320, 610).
        tool.start(pt(320, 610));
        tool.move(pt(360, 650)); // 40 px at zoom 2 is 20 world units
        tool.end(pt(360, 650));
        expect(ink.byId('i')!.samples[0], 50 + 20);
      });
    });

    test('a tap, a stray end after cancel, and no sink do not misfire', () {
      tool.start(pt(250, 300));
      tool.cancel();
      tool.end(pt(250, 300));
      expect(selection.isEmpty, isTrue);
    });
  });

  test('Ink.translated shifts x and y and nothing else; copyWith recolors', () {
    final s = line('i', 10, 20, 30);
    final t = s.translated(5, -3);
    expect([t.samples[0], t.samples[1], t.samples[2]], [15, 17, 0.5]);
    expect([t.samples[3], t.samples[4]], [35, 17]);
    expect(s.samples[0], 10, reason: 'the original is untouched');
    expect(t.id, s.id);
    expect(t.width, s.width);
    expect(s.copyWith(color: 7).color, 7);
    expect(s.copyWith().color, s.color);
  });
}
