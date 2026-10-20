import 'dart:ui';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:aether/features/canvas/links/link_remove_overlay.dart';
import 'package:aether/features/canvas/links/link_tool.dart';
import 'package:aether/features/canvas/links/links_layer.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
import 'package:aether/features/canvas/notes/notes_layer.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';

Link link(String id, String note, String hl) =>
    Link(id: id, docId: 'd', fromNoteId: note, toHighlightId: hl);

Highlight hl(String id, String page, Box r) => Highlight(
  id: id,
  docId: 'd',
  pageId: page,
  color: Swatch.claim,
  startChar: 0,
  endChar: 3,
  quote: 'q',
  rects: [r],
);

Note note(String id, {String? page = 'p0', double x = 400, double y = 300}) =>
    Note(
      id: id,
      docId: 'd',
      pageId: page,
      x: x,
      y: y,
      width: 200,
      height: 100,
      text: 'a note',
    );

ToolPoint pt(double x, double y) => ToolPoint(
  position: Offset(x, y),
  time: Duration.zero,
  kind: PointerDeviceKind.stylus,
);

class FakeLinkSink implements LinkSink {
  final List<(String, String)> added = [];
  @override
  void addLink(String noteId, String highlightId) =>
      added.add((noteId, highlightId));
}

void main() {
  group('LinksLayer', () {
    test('finds links by note, by highlight and by pair', () {
      final l = LinksLayer()
        ..add(link('1', 'n1', 'h1'))
        ..add(link('2', 'n1', 'h2'))
        ..add(link('3', 'n2', 'h1'));
      expect(l.forNote('n1').map((e) => e.id), ['1', '2']);
      expect(l.forHighlight('h1').map((e) => e.id), ['1', '3']);
      expect(l.between('n2', 'h1')!.id, '3');
      expect(l.between('n2', 'h2'), isNull);
    });

    test('selection follows removal and reload', () {
      final l = LinksLayer()..add(link('1', 'n', 'h'));
      l.select('1');
      expect(l.selectedId, '1');
      l.remove('1');
      expect(l.selectedId, isNull);
      l.add(link('2', 'n', 'h'));
      l.select('2');
      l.replaceAll([link('3', 'n', 'h')]);
      expect(l.selectedId, isNull, reason: 'the selected link is gone');
    });

    test('tells listeners only when something changes', () {
      final l = LinksLayer();
      var n = 0;
      l.addListener(() => n++);
      l.add(link('1', 'n', 'h'));
      l.select('1');
      l.select('1');
      l.remove('nope');
      expect(n, 2);
    });
  });

  group('LinkLayout', () {
    late NotesLayer notes;
    late HighlightLayer highlights;
    const scene = Scene([
      Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 600, 800)),
    ]);
    setUp(() {
      notes = NotesLayer()..add(note('n'));
      highlights = HighlightLayer()
        ..add(hl('h', 'p0', const Box(50, 500, 250, 512)));
    });

    test(
      'puts a link from the note edge to the highlight line, in world space',
      () {
        final e = LinkLayout(
          scene: scene,
          notes: notes,
          highlights: highlights,
        ).ends(link('l', 'n', 'h'))!;
        // Note at page (400,300) is world (500,400), 200x100; centre (600,450).
        // Highlight line world y = 100 + 506 = 606, x 150..350.
        expect(e.highlight.dy, 606);
        expect(e.highlight.dx, 350, reason: 'nearest point along the line');
        expect(
          e.note.dy,
          closeTo(500, 1e-6),
          reason: 'leaves by the bottom edge',
        );
      },
    );

    test('a link with a missing end has no place', () {
      final layout = LinkLayout(
        scene: scene,
        notes: notes,
        highlights: highlights,
      );
      expect(layout.ends(link('l', 'gone', 'h')), isNull);
      expect(layout.ends(link('l', 'n', 'gone')), isNull);
      notes.add(note('free', page: 'no-such-page'));
      expect(layout.ends(link('l', 'free', 'h')), isNull);
    });
  });

  group('LinkToolController', () {
    late ValueNotifier<ViewState> view;
    late ValueNotifier<Scene> scene;
    late NotesLayer notes;
    late HighlightLayer highlights;
    late LinksLayer links;
    late LiveLink live;
    late FakeLinkSink sink;
    late LinkToolController tool;

    // Page p0 at world (100,100). Highlight line: world y 600..612, x 150..350.
    // Note n: world (500,400)..(700,500).
    setUp(() {
      view = ValueNotifier(const ViewState());
      scene = ValueNotifier(
        const Scene([
          Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 600, 800)),
        ]),
      );
      notes = NotesLayer()..add(note('n'));
      highlights = HighlightLayer()
        ..add(hl('h', 'p0', const Box(50, 500, 250, 512)));
      links = LinksLayer();
      live = LiveLink();
      sink = FakeLinkSink();
      tool = LinkToolController(
        view: view,
        scene: scene,
        notes: notes,
        highlights: highlights,
        links: links,
        live: live,
        sink: sink,
      );
    });

    test('drag from a note to a highlight links them', () {
      tool.start(pt(600, 450));
      tool.move(pt(500, 520));
      expect(live.active, isTrue);
      tool.move(pt(300, 606));
      expect(live.target, isNotEmpty, reason: 'the target gets a halo');
      tool.end(pt(300, 606));
      expect(sink.added.single, ('n', 'h'));
      expect(live.active, isFalse);
    });

    test('and from a highlight to a note', () {
      tool.start(pt(200, 606));
      tool.move(pt(400, 500));
      tool.move(pt(600, 450));
      expect(live.target.single, const Rect.fromLTWH(500, 400, 200, 100));
      tool.end(pt(600, 450));
      expect(sink.added.single, ('n', 'h'), reason: 'always note first');
    });

    test('snaps to a target within 24 dp, not beyond', () {
      tool.start(pt(600, 450));
      tool.move(pt(300, 612 + 22)); // 22 below the line
      expect(live.target, isNotEmpty);
      tool.move(pt(300, 612 + 30));
      expect(live.target, isEmpty);
      tool.end(pt(300, 612 + 30));
      expect(sink.added, isEmpty, reason: 'nothing in reach, no link');
    });

    test('the reach is 24 dp at any zoom', () {
      view.value = const ViewState(zoom: 2);
      // Highlight line is at screen y 1200..1224 at zoom 2.
      tool.start(pt(1200, 900)); // inside the note (world 600,450)
      tool.move(pt(600, 1224 + 20));
      expect(live.target, isNotEmpty);
      tool.move(pt(600, 1224 + 30));
      expect(live.target, isEmpty);
      tool.cancel();
    });

    test('a drag that starts on bare canvas does nothing', () {
      tool.start(pt(50, 50));
      tool.move(pt(600, 450));
      tool.end(pt(600, 450));
      expect(sink.added, isEmpty);
      expect(live.active, isFalse);
    });

    test('a tap on a note or highlight links nothing', () {
      tool.start(pt(600, 450));
      tool.end(pt(600, 450));
      expect(sink.added, isEmpty);
    });

    test('a note to a note, or a highlight to a highlight, is not a link', () {
      notes.add(note('n2', x: 400, y: 600));
      tool.start(pt(600, 450));
      tool.move(pt(600, 700)); // over the other note
      expect(live.target, isEmpty);
      tool.end(pt(600, 700));
      expect(sink.added, isEmpty);
    });

    test('cancel drops the line', () {
      tool.start(pt(600, 450));
      tool.move(pt(500, 520));
      tool.cancel();
      expect(live.active, isFalse);
      tool.end(pt(300, 606)); // stray end: ignored
      expect(sink.added, isEmpty);
    });

    test('a press on a link line selects it; on bare canvas, deselects', () {
      links.add(link('l', 'n', 'h'));
      final e = LinkLayout(
        scene: scene.value,
        notes: notes,
        highlights: highlights,
      ).ends(link('l', 'n', 'h'))!;
      final mid = e.middle;
      tool.start(pt(mid.dx + 3, mid.dy));
      tool.end(pt(mid.dx + 3, mid.dy));
      expect(links.selectedId, 'l');
      tool.start(pt(900, 900));
      tool.end(pt(900, 900));
      expect(links.selectedId, isNull);
    });

    test('a press far from a line does not select it', () {
      links.add(link('l', 'n', 'h'));
      tool.start(pt(900, 900));
      expect(links.selectedId, isNull);
    });

    test('without a sink the tool does nothing', () {
      tool.sink = null;
      tool.start(pt(600, 450));
      tool.move(pt(300, 606));
      tool.end(pt(300, 606));
      expect(live.active, isFalse);
      expect(sink.added, isEmpty);
    });
  });

  group('painting', () {
    Future<ByteData> render(
      LinksLayer links,
      NotesLayer notes,
      HighlightLayer h, {
      int? selected,
    }) async {
      const scene = Scene([
        Card(id: 'p0', index: 0, rect: Rect.fromLTWH(0, 0, 400, 400)),
      ]);
      final rec = PictureRecorder();
      LinksPainter(
        view: ValueNotifier(const ViewState()),
        scene: ValueNotifier(scene),
        links: links,
        notes: notes,
        highlights: h,
        tokens: AetherTokens.light,
      ).paint(Canvas(rec), const Size(400, 400));
      final img = await rec.endRecording().toImage(400, 400);
      return (await img.toByteData())!;
    }

    int alpha(ByteData d, int x, int y) => d.getUint8((y * 400 + x) * 4 + 3);

    testWidgets('a link is an indigo curve ending in a dot on the highlight', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final notes = NotesLayer()..add(note('n', x: 20, y: 20));
        final h = HighlightLayer()
          ..add(hl('h', 'p0', const Box(100, 300, 300, 312)));
        final links = LinksLayer()..add(link('l', 'n', 'h'));
        final d = await render(links, notes, h);
        // The end dot sits on the highlight line, at the point nearest the note.
        var drawn = 0;
        for (var y = 0; y < 400; y += 2) {
          for (var x = 0; x < 400; x += 2) {
            if (alpha(d, x, y) > 0) drawn++;
          }
        }
        expect(drawn, greaterThan(40), reason: 'something is drawn');
        expect(alpha(d, 380, 380), 0, reason: 'and not everywhere');
        final o = (306 * 400 + 120) * 4;
        expect(
          alpha(d, 120, 306),
          greaterThan(0),
          reason: 'the dot at (120, 306)',
        );
        // Indigo: blue strongest.
        expect(d.getUint8(o + 2), greaterThan(d.getUint8(o)));
      });
    });

    testWidgets('a link to something missing is not drawn', (tester) async {
      await tester.runAsync(() async {
        final notes = NotesLayer()..add(note('n', x: 20, y: 20));
        final links = LinksLayer()..add(link('l', 'n', 'nope'));
        final d = await render(links, notes, HighlightLayer());
        var drawn = 0;
        for (var i = 3; i < 400 * 400 * 4; i += 4) {
          if (d.getUint8(i) > 0) drawn++;
        }
        expect(drawn, 0);
      });
    });
  });

  testWidgets(
    'the Remove link control appears on a selected link and removes it',
    (tester) async {
      final notes = NotesLayer()..add(note('n', x: 20, y: 20));
      final h = HighlightLayer()
        ..add(hl('h', 'p0', const Box(100, 300, 300, 312)));
      final links = LinksLayer()..add(link('l', 'n', 'h'));
      final removed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: Scaffold(
            body: LinkRemoveOverlay(
              view: ValueNotifier(const ViewState()),
              scene: ValueNotifier(
                const Scene([
                  Card(id: 'p0', index: 0, rect: Rect.fromLTWH(0, 0, 400, 400)),
                ]),
              ),
              links: links,
              notes: notes,
              highlights: h,
              onRemove: removed.add,
            ),
          ),
        ),
      );
      expect(find.text('Remove link'), findsNothing);
      links.select('l');
      await tester.pump();
      expect(find.text('Remove link'), findsOneWidget);
      expect(
        tester.getSize(find.byType(InkWell)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Remove link'));
      expect(removed, ['l']);
    },
  );
}
