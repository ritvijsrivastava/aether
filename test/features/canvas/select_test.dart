import 'dart:ui';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
import 'package:aether/features/canvas/notes/notes_layer.dart';
import 'package:aether/features/canvas/select/mark_hit.dart';
import 'package:aether/features/canvas/select/select_tool.dart';
import 'package:aether/features/canvas/select/selection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Ink line(String id, String? page, double x0, double y, double x1) => Ink(
  id: id,
  docId: 'd',
  pageId: page,
  samples: Float32List.fromList([x0, y, 0.5, x1, y, 0.5]),
  width: 4,
  color: 0xFF000000,
);

Highlight hl(String id, Box r) => Highlight(
  id: id,
  docId: 'd',
  pageId: 'p0',
  meaning: Meaning.claim,
  startChar: 0,
  endChar: 3,
  quote: 'q',
  rects: [r],
);

Note note(String id, double x, double y) => Note(
  id: id,
  docId: 'd',
  pageId: 'p0',
  x: x,
  y: y,
  width: 100,
  height: 60,
  text: 'n',
);

ToolPoint pt(double x, double y) => ToolPoint(
  position: Offset(x, y),
  time: Duration.zero,
  kind: PointerDeviceKind.stylus,
);

class FakeSelectSink implements SelectSink {
  final List<List<Mark>> moves = [];
  @override
  void commitMove(List<Mark> finals) => moves.add(finals);
}

void main() {
  // Page p0 at world (100, 100).
  const scene = Scene([
    Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 600, 800)),
  ]);
  late InkLayer ink;
  late HighlightLayer highlights;
  late NotesLayer notes;
  late MarkHitTester hit;

  setUp(() {
    ink = InkLayer();
    highlights = HighlightLayer();
    notes = NotesLayer();
    hit = MarkHitTester(
      scene: scene,
      ink: ink,
      highlights: highlights,
      notes: notes,
    );
  });

  group('SelectionState', () {
    test('sets, compares, prunes and groups by kind', () {
      final s = SelectionState();
      var n = 0;
      s.addListener(() => n++);
      s.set([
        const MarkRef(MarkKind.ink, 'a'),
        const MarkRef(MarkKind.note, 'b'),
      ]);
      s.set([
        const MarkRef(MarkKind.note, 'b'),
        const MarkRef(MarkKind.ink, 'a'),
      ]);
      expect(n, 1, reason: 'the same set again is not a change');
      expect(s.count, 2);
      expect(s.idsOf(MarkKind.ink), ['a']);
      s.prune((r) => r.id == 'a');
      expect(s.count, 1);
      s.clear();
      s.clear();
      expect(s.isEmpty, isTrue);
      expect(n, 3);
    });
  });

  group('MarkHitTester.markAt', () {
    test('a note is on top of ink and highlights', () {
      highlights.add(hl('h', const Box(50, 50, 300, 62)));
      ink.add(line('i', 'p0', 50, 56, 300));
      notes.add(note('n', 100, 40));
      // World (250, 156) is page (150, 56): highlight, stroke and note.
      expect(hit.markAt(const Offset(250, 156), 1)!.kind, MarkKind.note);
      expect(
        hit.markAt(const Offset(350, 156), 1)!.kind,
        MarkKind.ink,
        reason: 'outside the note, ink beats the highlight under it',
      );
    });

    test('a highlight is found where there is no ink or note', () {
      highlights.add(hl('h', const Box(50, 50, 300, 62)));
      ink.add(line('i', 'p0', 50, 200, 300)); // well below
      expect(hit.markAt(const Offset(250, 156), 1)!.kind, MarkKind.highlight);
      expect(hit.markAt(const Offset(250, 200 + 100), 1)!.kind, MarkKind.ink);
      expect(hit.markAt(const Offset(650, 700), 1), isNull);
    });

    test('free ink is found in canvas space', () {
      ink.add(line('free', null, 10, 20, 90));
      expect(hit.markAt(const Offset(50, 22), 1)!.id, 'free');
    });

    test('ink is within 10 dp at any zoom', () {
      ink.add(line('i', 'p0', 50, 56, 300)); // world y 156
      expect(hit.markAt(const Offset(250, 156 + 15), 1), isNull);
      expect(
        hit.markAt(const Offset(250, 156 + 15), 0.5),
        isNotNull,
        reason: 'zoomed out, 15 world units is 7.5 dp',
      );
    });
  });

  group('lasso and marquee', () {
    setUp(() {
      highlights.add(hl('h', const Box(50, 50, 250, 62))); // world y 150..162
      ink.add(line('i', 'p0', 50, 300, 250)); // world y 400
      notes.add(note('n', 400, 500)); // world (500,600)..(600,660)
      ink.add(line('far', 'p0', 50, 700, 250));
    });

    test('encloses the marks that are at least half inside', () {
      // A loop round the highlight and the stroke, not the note or far ink.
      final marks = hit.inLoop([140, 120, 400, 120, 400, 450, 140, 450]);
      expect({for (final m in marks) m.id}, {'h', 'i'});
    });

    test('a loop that only just clips a mark leaves it out', () {
      // Covers only the left quarter of the stroke (x 150..200 of 150..350).
      final marks = hit.inLoop([120, 380, 200, 380, 200, 420, 120, 420]);
      expect(marks, isEmpty);
    });

    test('a rectangle works the same way', () {
      final marks = hit.inRect(const Rect.fromLTRB(450, 550, 700, 700));
      expect(marks.single, const MarkRef(MarkKind.note, 'n'));
    });

    test('the box round a selection covers every mark in world space', () {
      final b = hit.unionBounds([
        const MarkRef(MarkKind.highlight, 'h'),
        const MarkRef(MarkKind.note, 'n'),
      ])!;
      expect(b.left, 150);
      expect(b.right, 600);
      expect(b.top, 150);
      expect(b.bottom, 660);
    });

    test('marks that are gone have no box', () {
      expect(hit.boundsOf(const MarkRef(MarkKind.ink, 'nope')), isNull);
      expect(hit.unionBounds([const MarkRef(MarkKind.note, 'nope')]), isNull);
    });
  });

  group('SelectToolController', () {
    late ValueNotifier<ViewState> view;
    late ValueNotifier<Scene> sceneN;
    late SelectionState selection;
    late LiveLasso lasso;
    late FakeSelectSink sink;
    late bool shift;
    late SelectToolController tool;

    setUp(() {
      view = ValueNotifier(const ViewState());
      sceneN = ValueNotifier(scene);
      selection = SelectionState();
      lasso = LiveLasso();
      sink = FakeSelectSink();
      shift = false;
      tool = SelectToolController(
        view: view,
        scene: sceneN,
        selection: selection,
        live: lasso,
        ink: ink,
        highlights: highlights,
        notes: notes,
        shift: () => shift,
        sink: sink,
      );
      highlights.add(hl('h', const Box(50, 50, 250, 62)));
      ink.add(line('i', 'p0', 50, 300, 250));
      notes.add(note('n', 400, 500));
    });

    test('a tap selects the mark under it; a tap on bare canvas clears', () {
      tool.start(pt(260, 400));
      tool.end(pt(260, 400));
      expect(selection.refs, {const MarkRef(MarkKind.ink, 'i')});
      tool.start(pt(660, 300));
      tool.end(pt(660, 300));
      expect(selection.isEmpty, isTrue);
    });

    test('a thin highlight can be selected with a finger tap beside it', () {
      tool.start(pt(260, 156 + 9)); // 9 below the rect
      tool.end(pt(260, 156 + 9));
      expect(selection.refs.single.kind, MarkKind.highlight);
    });

    test('drawing a loop selects what it encloses and shows the loop', () {
      tool.start(pt(120, 120));
      tool.move(pt(120, 200));
      expect(lasso.active, isTrue);
      tool.move(pt(400, 200));
      tool.move(pt(400, 120));
      tool.end(pt(130, 120));
      expect(selection.refs, {const MarkRef(MarkKind.highlight, 'h')});
      expect(lasso.active, isFalse);
    });

    test('Shift draws a rectangle', () {
      shift = true;
      tool.start(pt(450, 550));
      tool.move(pt(500, 600));
      expect(lasso.marquee, isTrue);
      tool.move(pt(700, 700));
      tool.end(pt(700, 700));
      expect(selection.refs, {const MarkRef(MarkKind.note, 'n')});
    });

    test('a new loop replaces the old selection', () {
      selection.set([const MarkRef(MarkKind.note, 'n')]);
      tool.start(pt(120, 120)); // outside the note's outline
      tool.move(pt(120, 200));
      tool.move(pt(400, 200));
      tool.move(pt(400, 120));
      tool.end(pt(130, 120));
      expect(selection.refs.single.id, 'h');
    });

    group('moving', () {
      setUp(() {
        selection.set([
          const MarkRef(MarkKind.ink, 'i'),
          const MarkRef(MarkKind.note, 'n'),
          const MarkRef(MarkKind.highlight, 'h'),
        ]);
      });

      test('dragging the selection moves ink and notes, not highlights', () {
        tool.start(pt(300, 400)); // inside the selection's outline
        tool.move(pt(340, 430));
        expect(ink.byId('i')!.samples[0], 90, reason: 'live, as it is dragged');
        expect(notes.byId('n')!.x, 440);
        expect(notes.byId('n')!.y, 530);
        tool.end(pt(340, 430));
        expect(
          highlights.byId('h')!.rects.single.x0,
          50,
          reason: 'text-anchored',
        );
        final done = sink.moves.single;
        expect({for (final m in done) m.id}, {'i', 'n'});
        expect(ink.byId('i')!.samples[1], 330);
      });

      test('an ink point keeps its pressure when moved', () {
        tool.start(pt(300, 400));
        tool.move(pt(340, 430));
        tool.end(pt(340, 430));
        expect(ink.byId('i')!.samples[2], 0.5);
      });

      test('a drag that goes nowhere saves nothing', () {
        tool.start(pt(300, 400));
        tool.move(pt(340, 430));
        tool.move(pt(300, 400));
        tool.end(pt(300, 400));
        expect(sink.moves, isEmpty);
      });

      test('cancel puts everything back', () {
        tool.start(pt(300, 400));
        tool.move(pt(360, 460));
        tool.cancel();
        expect(ink.byId('i')!.samples[0], 50);
        expect(notes.byId('n')!.x, 400);
        expect(sink.moves, isEmpty);
      });

      test(
        'a selection of only highlights does not move; the drag is a loop',
        () {
          selection.set([const MarkRef(MarkKind.highlight, 'h')]);
          tool.start(pt(260, 156));
          tool.move(pt(300, 300));
          expect(lasso.active, isTrue);
          tool.cancel();
          expect(highlights.byId('h')!.rects.single.x0, 50);
        },
      );

      test('the zoom and pan do not change what a move means', () {
        view.value = const ViewState(x: 20, y: 10, zoom: 2);
        // Ink world (150, 400) is screen (320, 810).
        tool.start(pt(340, 810));
        tool.move(pt(380, 850)); // 40 px at zoom 2 is 20 world units
        tool.end(pt(380, 850));
        expect(ink.byId('i')!.samples[0], 50 + 20);
      });
    });

    test('a tap, a stray end after cancel, and no sink do not misfire', () {
      tool.start(pt(260, 400));
      tool.cancel();
      tool.end(pt(260, 400));
      expect(selection.isEmpty, isTrue);
    });
  });

  test('Ink.translated shifts x and y and nothing else; copyWith recolors', () {
    final s = line('i', 'p0', 10, 20, 30);
    final t = s.translated(5, -3);
    expect([t.samples[0], t.samples[1], t.samples[2]], [15, 17, 0.5]);
    expect([t.samples[3], t.samples[4]], [35, 17]);
    expect(s.samples[0], 10, reason: 'the original is untouched');
    expect(t.id, s.id);
    expect(t.width, s.width);
    expect(s.copyWith(color: 7).color, 7);
    expect(s.copyWith().color, s.color);
    expect(
      hl('h', const Box(0, 0, 1, 1)).copyWith(meaning: Meaning.method).meaning,
      Meaning.method,
    );
  });
}
