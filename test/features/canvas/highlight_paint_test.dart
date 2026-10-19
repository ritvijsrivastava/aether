import 'dart:ui';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:aether/features/canvas/engine/page_surface.dart';
import 'package:aether/features/canvas/engine/painters.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page with a black bar standing in for a line of text, at page
/// (20, 20)..(80, 30).
class InkBarSurface implements PageSurface {
  @override
  Listenable? get repaint => null;
  @override
  String? get stats => null;
  @override
  void beginFrame() {}
  @override
  void endFrame() {}
  @override
  void paint(Canvas canvas, Card card, PageViewInfo info) => canvas.drawRect(
    Rect.fromLTWH(card.rect.left + 20, card.rect.top + 20, 60, 10),
    Paint()..color = const Color(0xFF000000),
  );
}

Highlight highlight(Meaning m, List<Box> rects, {int start = 0}) => Highlight(
  id: 'h-${rects.hashCode}',
  docId: 'd',
  pageId: 'p0',
  meaning: m,
  startChar: start,
  endChar: start < 0 ? -1 : 10,
  quote: 'q',
  rects: rects,
);

/// Renders the page at zoom 1 into pixels (100 x 100, the page at 0,0).
Future<ByteData> render({HighlightLayer? highlights, LiveMark? live}) async {
  final scene = ValueNotifier(
    const Scene([
      Card(id: 'p0', index: 0, rect: Rect.fromLTWH(0, 0, 100, 100)),
    ]),
  );
  final view = ValueNotifier(const ViewState());
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(100, 100);
  CardsPainter(
    view: view,
    scene: scene,
    surface: InkBarSurface(),
    tokens: AetherTokens.light,
    highlights: highlights,
  ).paint(canvas, size);
  if (live != null) {
    LiveMarkPainter(
      view: view,
      scene: scene,
      live: ValueNotifier(live),
    ).paint(canvas, size);
  }
  final image = await recorder.endRecording().toImage(100, 100);
  return (await image.toByteData())!;
}

(int, int, int) px(ByteData d, int x, int y) {
  final o = (y * 100 + x) * 4;
  return (d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2));
}

void expectClose((int, int, int) a, (int, int, int) b, {int tol = 3}) {
  expect((a.$1 - b.$1).abs(), lessThanOrEqualTo(tol), reason: '$a vs $b (r)');
  expect((a.$2 - b.$2).abs(), lessThanOrEqualTo(tol), reason: '$a vs $b (g)');
  expect((a.$3 - b.$3).abs(), lessThanOrEqualTo(tol), reason: '$a vs $b (b)');
}

void main() {
  // Paper #fffdfa under coral #f4877e at half strength, multiplied:
  // out = dst * (0.5 + 0.5 * src / 255) per channel.
  const paperUnderCoral = (249, 194, 187);

  testWidgets('a highlight tints the paper and leaves text black', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final layer = HighlightLayer()
        ..add(highlight(Meaning.claim, const [Box(10, 15, 90, 35)]));
      final d = await render(highlights: layer);
      expectClose(px(d, 12, 17), paperUnderCoral);
      expectClose(px(d, 50, 25), (0, 0, 0), tol: 1); // the "text"
      expectClose(px(d, 50, 60), (255, 253, 250), tol: 1); // untouched paper
    });
  }, tags: const []);

  testWidgets('each meaning has its own colour', (tester) async {
    await tester.runAsync(() async {
      Future<(int, int, int)> under(Meaning m) async {
        final layer = HighlightLayer()
          ..add(highlight(m, const [Box(10, 50, 90, 70)]));
        return px(await render(highlights: layer), 50, 60);
      }

      final claim = await under(Meaning.claim);
      final method = await under(Meaning.method);
      final question = await under(Meaning.question);
      expect(claim.$1, greaterThan(claim.$2), reason: 'coral is warm');
      expect(method.$3, lessThan(method.$1), reason: 'amber has little blue');
      expect(question.$3, greaterThan(question.$1), reason: 'blue is blue');
      expect({claim, method, question}.length, 3);
    });
  });

  testWidgets('overlapping highlights get darker, as marker does', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final layer = HighlightLayer()
        ..add(highlight(Meaning.claim, const [Box(10, 50, 60, 70)]))
        ..add(highlight(Meaning.method, const [Box(40, 50, 90, 70)]));
      final d = await render(highlights: layer);
      final one = px(d, 20, 60), both = px(d, 50, 60);
      expect(both.$2, lessThan(one.$2));
    });
  });

  testWidgets('a highlight stays on its own page', (tester) async {
    await tester.runAsync(() async {
      final layer = HighlightLayer()
        ..add(
          Highlight(
            id: 'x',
            docId: 'd',
            pageId: 'some-other-page',
            meaning: Meaning.claim,
            startChar: 0,
            endChar: 1,
            quote: 'q',
            rects: const [Box(10, 50, 90, 70)],
          ),
        );
      final d = await render(highlights: layer);
      expectClose(px(d, 50, 60), (255, 253, 250), tol: 1);
    });
  });

  testWidgets('a region highlight has an edge in its own colour', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final layer = HighlightLayer()
        ..add(
          highlight(Meaning.question, const [Box(10, 50, 90, 80)], start: -1),
        );
      final d = await render(highlights: layer);
      final inside = px(d, 50, 65);
      final edge = px(d, 50, 50); // on the top edge
      expect(edge.$1, lessThan(inside.$1), reason: 'the edge is stronger');
    });
  });

  testWidgets('the live preview paints over the page, clipped to it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final live = LiveMark(
        'p0',
        TextSelector.region(10, 50, 90, 70)!,
        Meaning.claim,
      );
      final d = await render(live: live);
      expect(px(d, 50, 60).$2, lessThan(200), reason: 'tinted');
      expectClose(px(d, 50, 90), (255, 253, 250), tol: 1);
    });
  });

  test('HighlightLayer keeps pages apart and replaces by id', () {
    final layer = HighlightLayer();
    final a = highlight(Meaning.claim, const [Box(0, 0, 10, 10)]);
    layer.add(a);
    expect(layer.forPage('p0'), [a]);
    expect(layer.forPage('nope'), isEmpty);
    layer.replaceAll([]);
    expect(layer.count, 0);
    expect(layer.forPage('p0'), isEmpty);
  });
}
