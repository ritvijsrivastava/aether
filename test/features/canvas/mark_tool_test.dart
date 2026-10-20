import 'dart:async';
import 'dart:ui';

import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/text/page_text.dart';
import 'package:aether/domain/text/page_text_source.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/marks/mark_layers.dart';
import 'package:aether/features/canvas/marks/mark_tool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Glyphs 6 wide, 10 tall, lines 14 apart from y = 100, x from 72.
PageText layout(List<String> lines) {
  final codes = <int>[];
  final boxes = <double>[];
  for (var l = 0; l < lines.length; l++) {
    final y = 100.0 + l * 14;
    var x = 72.0;
    for (final r in lines[l].runes) {
      codes.add(r);
      boxes.addAll([x, y, x + 6, y + 10]);
      x += 6;
    }
    if (l < lines.length - 1) {
      codes.add(0x0A);
      boxes.addAll([0, 0, 0, 0]);
    }
  }
  return PageText.build(Int32List.fromList(codes), Float32List.fromList(boxes));
}

class FakeText implements PageTextSource {
  FakeText(this.pages);
  final Map<int, PageText> pages;

  /// When set, `peek` knows nothing and `pageText` waits for this.
  Completer<void>? gate;
  int requests = 0;

  @override
  PageText? peek(int i) => gate == null ? pages[i] : null;

  @override
  Future<PageText> pageText(int i) async {
    requests++;
    await gate?.future;
    return pages[i] ?? PageText.empty;
  }
}

class Added {
  Added(this.id, this.pageId, this.selection, this.color);
  final String id, pageId;
  final MarkSelection selection;
  final int color;
}

class FakeSink implements MarkSink {
  final List<Added> added = [];
  final List<(String old, Added now)> replaced = [];
  int _n = 0;

  @override
  String addHighlight({
    required String pageId,
    required MarkSelection selection,
    required int color,
    PageText? text,
  }) {
    final a = Added('h${++_n}', pageId, selection, color);
    added.add(a);
    return a.id;
  }

  @override
  String replaceHighlight({
    required String oldId,
    required String pageId,
    required MarkSelection selection,
    required int color,
    PageText? text,
  }) {
    final a = Added('h${++_n}', pageId, selection, color);
    replaced.add((oldId, a));
    return a.id;
  }
}

void main() {
  final page = layout(['the quick brown', 'fox jumps over.', 'Then it sat.']);

  late ValueNotifier<ViewState> view;
  late ValueNotifier<Scene> scene;
  late ValueNotifier<LiveMark?> live;
  late FakeText text;
  late FakeSink sink;
  late int color;
  late DateTime clock;
  late MarkToolController tool;

  setUp(() {
    view = ValueNotifier(const ViewState());
    scene = ValueNotifier(
      const Scene([
        Card(id: 'p0', index: 0, rect: Rect.fromLTWH(0, 0, 612, 792)),
        Card(id: 'p1', index: 1, rect: Rect.fromLTWH(0, 872, 612, 792)),
      ]),
    );
    live = ValueNotifier(null);
    text = FakeText({0: page, 1: page});
    sink = FakeSink();
    color = Swatch.claim;
    clock = DateTime(2030);
    tool = MarkToolController(
      view: view,
      scene: scene,
      live: live,
      color: () => color,
      text: text,
      sink: sink,
      now: () => clock,
    );
  });

  // "quick" is x 96..126, y 100..110; "jumps" is x 102..132, y 114..124.
  const quick = Offset(110, 105);
  const jumps = Offset(115, 119);

  group('dragging over text', () {
    test('previews while moving and commits one highlight on release', () {
      tool.markStart(quick);
      expect(live.value, isNull, reason: 'nothing to show before it moves');
      tool.markMove(const Offset(120, 108));
      expect(live.value!.selection.quote, 'quick');
      tool.markMove(jumps);
      expect(live.value!.selection.quote, 'quick brown fox jumps');
      expect(live.value!.cardId, 'p0');
      expect(live.value!.color, Swatch.claim);
      expect(sink.added, isEmpty, reason: 'only a release commits');
      tool.markEnd(jumps);
      expect(live.value, isNull);
      final a = sink.added.single;
      expect(a.pageId, 'p0');
      expect(a.selection.quote, 'quick brown fox jumps');
      expect(a.selection.rects.length, 2);
    });

    test('uses the meaning chosen at the moment of release', () {
      tool.markStart(quick);
      tool.markMove(jumps);
      color = Swatch.question;
      tool.markEnd(jumps);
      expect(sink.added.single.color, Swatch.question);
    });

    test('works in page space on the second page', () {
      // Page 1's card starts at y = 872.
      tool.markStart(const Offset(110, 872 + 105));
      tool.markMove(const Offset(115, 872 + 119));
      tool.markEnd(const Offset(115, 872 + 119));
      expect(sink.added.single.pageId, 'p1');
      expect(sink.added.single.selection.quote, 'quick brown fox jumps');
    });

    test('follows the pan and zoom of the view', () {
      // Zoom 2, panned by (-50, -20): screen = world * 2 + (-50, -20).
      view.value = const ViewState(x: -50, y: -20, zoom: 2);
      Offset at(Offset page) => page * 2 + const Offset(-50, -20);
      tool.markStart(at(quick));
      tool.markMove(at(jumps));
      tool.markEnd(at(jumps));
      expect(sink.added.single.selection.quote, 'quick brown fox jumps');
    });

    test(
      'the grab tolerance is 10 dp, so wider in page units when zoomed out',
      () {
        // 8 dp above "quick" at zoom 1 is within reach...
        tool.markStart(const Offset(110, 92));
        tool.markMove(jumps);
        tool.markEnd(jumps);
        expect(sink.added, hasLength(1));
        sink.added.clear();
        // ...but 15 dp above is not, so it starts a rectangle instead.
        tool.markStart(const Offset(110, 85));
        tool.markMove(jumps);
        tool.markEnd(jumps);
        expect(sink.added.single.selection.isRegion, isTrue);
      },
    );

    test('leaving the page mid-drag keeps selecting on that page', () {
      tool.markStart(quick);
      tool.markMove(const Offset(900, 2000)); // far below and right, off page
      tool.markEnd(const Offset(900, 2000));
      expect(sink.added.single.pageId, 'p0');
      expect(sink.added.single.selection.quote, endsWith('sat.'));
    });

    test('Escape or any interruption makes nothing', () {
      tool.markStart(quick);
      tool.markMove(jumps);
      tool.markCancel();
      expect(live.value, isNull);
      expect(sink.added, isEmpty);
      tool.markEnd(jumps); // a stray end after a cancel is ignored
      expect(sink.added, isEmpty);
    });
  });

  group('free rectangle', () {
    test('a drag from empty paper makes a region highlight', () {
      tool.markStart(const Offset(400, 500));
      tool.markMove(const Offset(450, 560));
      expect(live.value!.selection.isRegion, isTrue);
      tool.markEnd(const Offset(450, 560));
      final s = sink.added.single.selection;
      expect(s.isRegion, isTrue);
      expect(s.quote, '(image region)');
      expect(s.rects.single.width, 50);
      expect(s.rects.single.height, 60);
    });

    test('a page without text is always a rectangle', () {
      text.pages[0] = PageText.empty;
      tool.markStart(quick);
      tool.markMove(jumps);
      tool.markEnd(jumps);
      expect(sink.added.single.selection.isRegion, isTrue);
    });

    test('a tap on empty paper is nothing', () {
      tool.markStart(const Offset(400, 500));
      tool.markEnd(const Offset(400, 500));
      expect(sink.added, isEmpty);
    });
  });

  group('taps', () {
    test('a tap highlights the word', () {
      tool.markStart(quick);
      tool.markEnd(quick);
      expect(sink.added.single.selection.quote, 'quick');
    });

    test('a wobble within 6 dp is still a tap', () {
      tool.markStart(quick);
      tool.markMove(quick + const Offset(3, 2));
      expect(live.value, isNull);
      tool.markEnd(quick + const Offset(3, 2));
      expect(sink.added.single.selection.quote, 'quick');
    });

    test('a second tap soon after widens the word to its sentence', () {
      const fox = Offset(80, 119);
      tool.markStart(fox);
      tool.markEnd(fox);
      clock = clock.add(const Duration(milliseconds: 200));
      tool.markStart(fox);
      tool.markEnd(fox);
      expect(sink.added, hasLength(1), reason: 'the second tap is not new');
      final (old, now) = sink.replaced.single;
      expect(old, sink.added.single.id);
      expect(now.selection.quote, 'the quick brown fox jumps over.');
    });

    test('a slow second tap is a new word, not a double tap', () {
      tool.markStart(quick);
      tool.markEnd(quick);
      clock = clock.add(const Duration(milliseconds: 600));
      tool.markStart(quick);
      tool.markEnd(quick);
      expect(sink.added, hasLength(2));
      expect(sink.replaced, isEmpty);
    });

    test('a second tap elsewhere is a new word', () {
      tool.markStart(quick);
      tool.markEnd(quick);
      clock = clock.add(const Duration(milliseconds: 100));
      tool.markStart(const Offset(200, 105 + 28)); // third line, far away
      tool.markEnd(const Offset(200, 105 + 28));
      expect(sink.replaced, isEmpty);
    });

    test('a third tap starts over rather than widening again', () {
      tool.markStart(quick);
      tool.markEnd(quick);
      clock = clock.add(const Duration(milliseconds: 100));
      tool.markStart(quick);
      tool.markEnd(quick);
      clock = clock.add(const Duration(milliseconds: 100));
      tool.markStart(quick);
      tool.markEnd(quick);
      expect(sink.replaced, hasLength(1));
      expect(sink.added, hasLength(2));
    });
  });

  group('text still loading', () {
    test('a drag that starts before the text arrives catches up', () async {
      text.gate = Completer<void>();
      tool.markStart(quick);
      tool.markMove(jumps);
      expect(live.value, isNull, reason: 'no text yet, nothing to show');
      text.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(live.value!.selection.quote, 'quick brown fox jumps');
      tool.markEnd(jumps);
      expect(sink.added.single.selection.quote, 'quick brown fox jumps');
    });

    test('a wait is counted and timed for the overlay', () async {
      expect(tool.stats, 'text always ready');
      text.gate = Completer<void>();
      tool.markStart(quick);
      clock = clock.add(const Duration(milliseconds: 180));
      text.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      tool.markEnd(quick);
      expect(tool.waits, 1);
      expect(tool.lastWait, const Duration(milliseconds: 180));
      expect(tool.maxWait, const Duration(milliseconds: 180));
      expect(tool.stats, 'text waited 1× · last 180 ms · max 180 ms');
      // A mark whose text is ready adds nothing.
      text.gate = null;
      tool.markStart(quick);
      tool.markEnd(quick);
      expect(tool.waits, 1);
    });

    test('releasing before the text arrives still finishes the mark', () async {
      text.gate = Completer<void>();
      tool.markStart(quick);
      tool.markMove(jumps);
      tool.markEnd(jumps);
      expect(sink.added, isEmpty);
      text.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(sink.added.single.selection.quote, 'quick brown fox jumps');
    });

    test('a gesture that was cancelled while loading is dropped', () async {
      text.gate = Completer<void>();
      tool.markStart(quick);
      tool.markCancel();
      text.gate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(sink.added, isEmpty);
      expect(live.value, isNull);
    });
  });

  group('not ready', () {
    test('without text or a sink the tool does nothing', () {
      tool.text = null;
      tool.markStart(quick);
      tool.markMove(jumps);
      tool.markEnd(jumps);
      expect(sink.added, isEmpty);
      expect(tool.isActive, isFalse);
    });

    test('a press off every page does nothing', () {
      tool.markStart(const Offset(5000, 5000));
      tool.markMove(jumps);
      tool.markEnd(jumps);
      expect(sink.added, isEmpty);
    });
  });

  test('warmVisible loads the text of the pages in view', () async {
    tool.warmVisible(viewport: const Size(800, 1000));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(text.requests, greaterThanOrEqualTo(1));
    tool.dispose();
  });
}
