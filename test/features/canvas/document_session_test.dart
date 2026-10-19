import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/data/pdf/pdf_storage.dart';
import 'package:aether/domain/commands/command.dart';
import 'package:aether/domain/ops/entity_state.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/core/geometry/box.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:aether/features/canvas/select/selection.dart';
import 'package:aether/domain/ops/op_store.dart';
import 'package:aether/domain/text/page_text.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:aether/features/canvas/document_session.dart';
import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/library/import/pdf_importer.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// Glyphs 6 wide, 10 tall, lines 14 apart from y = 100, x from 72.
PageText layoutText(List<String> lines) {
  final codes = <int>[];
  final boxes = <double>[];
  for (var l = 0; l < lines.length; l++) {
    var x = 72.0;
    for (final r in lines[l].runes) {
      codes.add(r);
      boxes.addAll([x, 100.0 + l * 14, x + 6, 110.0 + l * 14]);
      x += 6;
    }
    if (l < lines.length - 1) {
      codes.add(0x0A);
      boxes.addAll([0, 0, 0, 0]);
    }
  }
  return PageText.build(Int32List.fromList(codes), Float32List.fromList(boxes));
}

/// A store whose writes can be made to fail.
class FlakyStore implements OpStore {
  FlakyStore(this.inner);
  final OpStore inner;
  bool failCommits = false;

  @override
  Future<void> commit(List<Op> ops) =>
      failCommits ? Future.error(StateError('disk full')) : inner.commit(ops);
  @override
  Future<EntityState?> entity(String id) => inner.entity(id);
  @override
  Future<List<EntityState>> entities({
    EntityKind? kind,
    String? docId,
    bool includeDeleted = false,
  }) =>
      inner.entities(kind: kind, docId: docId, includeDeleted: includeDeleted);
  @override
  Future<List<Op>> allOps() => inner.allOps();
  @override
  Future<Hlc?> latestHlc() => inner.latestHlc();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late AetherDatabase db;
  late DriftOpStore store;
  late String docId;
  var clockTick = 0;

  DocumentSession open({
    String? id,
    Duration delay = const Duration(milliseconds: 40),
    Duration noteDelay = const Duration(milliseconds: 30),
  }) {
    final controller = CanvasController(scene: const Scene([]))
      ..viewport = const Size(1000, 800);
    addTearDown(controller.dispose);
    final session = DocumentSession(
      docId: id ?? docId,
      store: store,
      db: db,
      controller: controller,
      clock: HlcClock('dev', now: () => 5000 + clockTick++),
      ids: SequentialIdGenerator('s${clockTick++}'),
      viewSaveDelay: delay,
      noteEditDelay: noteDelay,
    );
    // Flushes a pending view save before the database is closed.
    addTearDown(session.dispose);
    return session;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aether_session_');
    db = AetherDatabase(NativeDatabase.memory());
    store = DriftOpStore(db);
    final storage = await PdfStorage.open(Directory('${tmp.path}/lib'));
    var t = 1000;
    final importer = PdfImporter(
      store: store,
      bus: CommandBus(
        store: store,
        clock: HlcClock('imp', now: () => t++),
        ids: SequentialIdGenerator('i'),
      ),
      storage: storage,
      inspector: FakeInspector(),
      db: db,
      ids: SequentialIdGenerator('doc'),
    );
    final src = writeFakePdf(
      await Directory('${tmp.path}/src').create(),
      'a.pdf',
    );
    docId = (await importer.import(ImportRequest(src.path))).docId;
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<Offset> storedPos(DocumentSession s, int index) async {
    final pages = [
      for (final e in await store.entities(kind: EntityKind.page, docId: docId))
        PageRef.fromState(e),
    ]..sort((a, b) => a.index.compareTo(b.index));
    return Offset(pages[index].cardX, pages[index].cardY);
  }

  void drag(DocumentSession s, int index, Offset screenDelta) {
    final c = s.controller;
    c.cardDragStart(c.scene.value.cards[index].id);
    c.cardDragBy(screenDelta);
    c.cardDragEnd();
  }

  group('loading', () {
    test('a missing, deleted or non-document id does not load', () async {
      expect(await open(id: 'nope').load(), isFalse);

      final pageId = (await store.entities(kind: EntityKind.page)).first.id;
      expect(
        await open(id: pageId).load(),
        isFalse,
        reason: 'a page is not a document',
      );

      final bus = CommandBus(
        store: store,
        clock: HlcClock('x', now: () => 9000 + clockTick++),
        ids: SequentialIdGenerator('d'),
      );
      await bus.run(await CommandFactory(store).delete(docId));
      expect(await open().load(), isFalse);
    });

    test(
      'puts the stored pages on the canvas, in order, at their positions',
      () async {
        final s = open();
        expect(await s.load(), isTrue);
        expect(s.document!.title, 'a');
        final cards = s.controller.scene.value.cards;
        expect(cards.length, 3);
        expect(cards.map((c) => c.index), [0, 1, 2]);
        expect(cards[0].rect, const Rect.fromLTWH(90, 0, 612, 792));
        expect(cards[1].rect.top, 872);
        expect(cards[2].rect.size, const Size(792, 612));
        expect(s.pageSizes(), [
          const Size(612, 792),
          const Size(612, 792),
          const Size(792, 612),
        ]);
      },
    );
  });

  group('moving cards', () {
    test(
      'a drag is saved as the card\'s new position, in world units',
      () async {
        final s = open();
        await s.load();
        s.controller.setView(const ViewState(zoom: 0.5));
        final before = await storedPos(s, 1);
        drag(s, 1, const Offset(50, 20)); // 100 x 40 world units at 0.5x
        await s.settled();
        expect(await storedPos(s, 1), before + const Offset(100, 40));
        expect(
          await storedPos(s, 0),
          const Offset(90, 0),
          reason: 'other pages untouched',
        );
      },
    );

    test('undo and redo move the card back and forth, on the canvas and in storage', () async {
      final s = open();
      await s.load();
      final before = await storedPos(s, 0);
      drag(s, 0, const Offset(30, 10));
      await s.settled();
      final moved = await storedPos(s, 0);
      expect(moved, before + const Offset(30, 10));

      await s.undo();
      expect(await storedPos(s, 0), before);
      expect(s.controller.scene.value.cards[0].rect.topLeft, before);

      await s.redo();
      expect(await storedPos(s, 0), moved);
      expect(s.controller.scene.value.cards[0].rect.topLeft, moved);
    });

    test(
      'quick successive drags apply in order and each undoes separately',
      () async {
        final s = open();
        await s.load();
        final start = await storedPos(s, 2);
        drag(s, 2, const Offset(10, 0));
        drag(s, 2, const Offset(0, 20));
        drag(s, 2, const Offset(5, 5));
        await s.settled();
        expect(await storedPos(s, 2), start + const Offset(15, 25));
        await s.undo();
        expect(await storedPos(s, 2), start + const Offset(10, 20));
        await s.undo();
        expect(await storedPos(s, 2), start + const Offset(10, 0));
        await s.undo();
        expect(await storedPos(s, 2), start);
        await s.undo(); // nothing left: harmless
        expect(await storedPos(s, 2), start);
      },
    );

    test('a new move after an undo clears redo', () async {
      final s = open();
      await s.load();
      drag(s, 0, const Offset(10, 10));
      await s.settled();
      await s.undo();
      expect(s.bus.canRedo, isTrue);
      drag(s, 0, const Offset(1, 1));
      await s.settled();
      expect(s.bus.canRedo, isFalse);
    });

    test('moves survive closing and reopening the document', () async {
      var s = open();
      await s.load();
      drag(s, 1, const Offset(77, 33));
      await s.settled();
      final expected = await storedPos(s, 1);
      await s.dispose();

      s = open();
      await s.load();
      expect(s.controller.scene.value.cards[1].rect.topLeft, expected);
    });

    test('history changes are announced, so the buttons can refresh', () async {
      final s = open();
      await s.load();
      var events = 0;
      final sub = s.bus.changes.listen((_) => events++);
      drag(s, 0, const Offset(5, 5));
      await s.settled();
      await s.undo();
      await Future<void>.delayed(Duration.zero);
      expect(events, 2);
      await sub.cancel();
    });
  });

  group('remembered view', () {
    test('nothing is saved until the view changes', () async {
      final s = open();
      await s.load();
      expect(await s.savedView(), isNull);
    });

    test('the view is saved shortly after it stops changing, and restored next time', () async {
      var s = open();
      await s.load();
      s.controller.setView(const ViewState(x: -120, y: -340, zoom: 1.5));
      expect(await s.savedView(), isNull, reason: 'debounced, not yet');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final saved = await s.savedView();
      expect((saved!.x, saved.y, saved.zoom), (-120, -340, 1.5));
      await s.dispose();

      s = open();
      await s.load();
      expect((await s.savedView())!.zoom, 1.5);
    });

    test('many quick changes save once, with the last value', () async {
      final s = open(delay: const Duration(milliseconds: 80));
      await s.load();
      for (var i = 1; i <= 10; i++) {
        s.controller.setView(ViewState(x: -i * 10.0, y: 0, zoom: 1));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect((await s.savedView())!.x, -100);
    });

    test('closing saves a change that is still waiting', () async {
      final s = open(delay: const Duration(seconds: 30));
      await s.load();
      s.controller.setView(const ViewState(x: -5, y: -6, zoom: 2));
      await s.dispose();
      final row = await db.viewState(docId);
      expect((row!.x, row.y, row.zoom), (-5, -6, 2));
    });

    test('each document remembers its own view', () async {
      final s = open();
      await s.load();
      s.controller.setView(const ViewState(x: -1, y: -2, zoom: 1.25));
      await s.dispose();
      expect(await db.viewState('some-other-doc'), isNull);
    });
  });

  group('highlights', () {
    final text = layoutText(['the quick brown', 'fox jumps over.']);
    MarkSelection pick(int a, int b) => TextSelector.between(text, a, b)!;

    Future<List<EntityState>> storedMarks() =>
        store.entities(kind: EntityKind.mark, docId: docId);

    Future<DocumentSession> opened() async {
      final s = open();
      await s.load();
      return s;
    }

    test('a new highlight shows at once and is saved behind it', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      final id = s.addHighlight(
        pageId: page.id,
        selection: pick(1, 4),
        meaning: Meaning.method,
        text: text,
      );
      expect(s.highlights.count, 1, reason: 'visible before it is written');
      expect(s.highlights.byId(id)!.quote, 'quick brown fox jumps');
      await s.settled();
      final saved = await storedMarks();
      expect(saved.single.id, id);
      final back = Mark.fromState(saved.single) as Highlight;
      expect(back.meaning, Meaning.method);
      expect(back.pageId, page.id);
      expect(back.quote, 'quick brown fox jumps');
      expect(back.rects.length, 2);
      expect(back.startChar, text.words[1].start);
      expect(back.endChar, text.words[4].end);
      expect(back.contextBefore, 'the');
      expect(back.contextAfter, 'over.');
    });

    test('highlights come back when the document is reopened', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards[1];
      s.addHighlight(
        pageId: page.id,
        selection: pick(0, 0),
        meaning: Meaning.claim,
        text: text,
      );
      s.addHighlight(
        pageId: page.id,
        selection: TextSelector.region(10, 20, 110, 70)!,
        meaning: Meaning.question,
      );
      await s.settled();
      final again = await opened();
      expect(again.highlights.count, 2);
      expect(again.highlights.forPage(page.id).length, 2);
      final region = again.highlights
          .forPage(page.id)
          .firstWhere((h) => h.startChar < 0);
      expect(region.quote, '(image region)');
      expect(region.meaning, Meaning.question);
      expect(region.rects.single, const Box(10, 20, 110, 70));
    });

    test('undo takes a highlight off the page, redo puts it back', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      s.addHighlight(
        pageId: page.id,
        selection: pick(0, 0),
        meaning: Meaning.claim,
        text: text,
      );
      await s.settled();
      expect(s.bus.undoLabel, 'Highlight');
      await s.undo();
      expect(s.highlights.count, 0);
      expect(await storedMarks(), isEmpty);
      await s.redo();
      expect(s.highlights.count, 1);
      expect((await storedMarks()).length, 1);
    });

    test('replacing is one step: undo brings the old one back', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      final word = s.addHighlight(
        pageId: page.id,
        selection: pick(1, 1),
        meaning: Meaning.claim,
        text: text,
      );
      final sentence = s.replaceHighlight(
        oldId: word,
        pageId: page.id,
        selection: TextSelector.sentenceAt(text, 1)!,
        meaning: Meaning.claim,
        text: text,
      );
      expect(s.highlights.byId(word), isNull);
      expect(s.highlights.byId(sentence)!.quote, contains('jumps over.'));
      await s.settled();
      expect((await storedMarks()).single.id, sentence);

      await s.undo();
      expect(s.highlights.count, 1);
      expect(s.highlights.byId(word)!.quote, 'quick');
      await s.undo();
      expect(s.highlights.count, 0);
    });

    test('deleting is undoable and survives a reopen', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      final id = s.addHighlight(
        pageId: page.id,
        selection: pick(0, 0),
        meaning: Meaning.claim,
        text: text,
      );
      await s.settled();
      s.deleteHighlight(id);
      expect(s.highlights.count, 0, reason: 'gone at once');
      await s.settled();
      expect(await storedMarks(), isEmpty);
      expect((await opened()).highlights.count, 0);

      await s.undo();
      expect(s.highlights.byId(id), isNotNull);
      expect((await storedMarks()).single.id, id);
      s.deleteHighlight('no-such-highlight'); // quietly nothing
      await s.settled();
      expect(s.highlights.count, 1);
    });

    test(
      'leaving the document right after marking still saves the mark',
      () async {
        final s = await opened();
        s.addHighlight(
          pageId: s.controller.scene.value.cards.first.id,
          selection: pick(0, 0),
          meaning: Meaning.claim,
          text: text,
        );
        await s.dispose(); // no settled() first, as when the screen is popped
        expect((await storedMarks()).length, 1);
      },
    );

    test('committing a mark costs the UI isolate under 5 ms', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      final sel = pick(0, 4); // two lines of text
      // Warm up, then time only the synchronous part: the optimistic add. The
      // write itself runs behind the queue.
      for (var i = 0; i < 20; i++) {
        s.addHighlight(
          pageId: page.id,
          selection: sel,
          meaning: Meaning.claim,
          text: text,
        );
      }
      final sw = Stopwatch()..start();
      const n = 100;
      for (var i = 0; i < n; i++) {
        s.addHighlight(
          pageId: page.id,
          selection: sel,
          meaning: Meaning.claim,
          text: text,
        );
      }
      final ms = sw.elapsedMicroseconds / n / 1000;
      // ignore: avoid_print
      print('addHighlight on the UI isolate: ${ms.toStringAsFixed(3)} ms');
      expect(ms, lessThan(5));
      await s.settled();
    });

    test('a failed save takes the highlight back off the page', () async {
      final flaky = FlakyStore(store);
      final controller = CanvasController(scene: const Scene([]))
        ..viewport = const Size(1000, 800);
      addTearDown(controller.dispose);
      final s = DocumentSession(
        docId: docId,
        store: flaky,
        db: db,
        controller: controller,
        clock: HlcClock('dev', now: () => 7000 + clockTick++),
        ids: SequentialIdGenerator('f${clockTick++}'),
      );
      addTearDown(s.dispose);
      await s.load();
      flaky.failCommits = true;
      s.addHighlight(
        pageId: controller.scene.value.cards.first.id,
        selection: pick(0, 0),
        meaning: Meaning.claim,
        text: text,
      );
      expect(s.highlights.count, 1);
      await s.settled();
      expect(s.highlights.count, 0, reason: 'never left looking saved');
      expect(await storedMarks(), isEmpty);
    });

    test('the highlight layer tells listeners when it changes', () async {
      final s = await opened();
      var changes = 0;
      s.highlights.addListener(() => changes++);
      final page = s.controller.scene.value.cards.first;
      final id = s.addHighlight(
        pageId: page.id,
        selection: pick(0, 0),
        meaning: Meaning.claim,
        text: text,
      );
      expect(changes, 1);
      s.highlights.remove(id);
      expect(changes, 2);
      s.highlights.remove(id); // already gone: no notification
      expect(changes, 2);
    });
  });

  group('ink', () {
    Float32List line([double y = 100]) => Float32List.fromList([
      10, y, 0.4, //
      60, y + 5, 0.6,
      110, y, 0.5,
    ]);

    Future<List<EntityState>> storedInk() async => [
      for (final e in await store.entities(kind: EntityKind.mark, docId: docId))
        if (e.field<String>(F.type) == 'ink') e,
    ];

    Future<DocumentSession> opened() async {
      final s = open();
      await s.load();
      return s;
    }

    test('a stroke shows at once and is saved behind it', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      final id = s.addInk(
        pageId: page.id,
        samples: line(),
        width: 3,
        color: 0xFFF4877E,
      );
      expect(s.ink.count, 1, reason: 'visible before it is written');
      await s.settled();
      final saved = (await storedInk()).single;
      expect(saved.id, id);
      final back = Mark.fromState(saved) as Ink;
      expect(back.pageId, page.id);
      expect(back.width, 3);
      expect(back.color, 0xFFF4877E);
      expect(back.samples, line());
      expect(s.bus.undoLabel, 'Ink');
    });

    test(
      'strokes come back when the document is reopened, free ones too',
      () async {
        final s = await opened();
        final page = s.controller.scene.value.cards[1];
        s.addInk(
          pageId: page.id,
          samples: line(),
          width: 2.5,
          color: 0xFF2B2723,
        );
        s.addInk(samples: line(300), width: 2.5, color: 0xFF2B2723);
        await s.settled();
        final again = await opened();
        expect(again.ink.count, 2);
        expect(again.ink.forPage(page.id).length, 1);
        expect(again.ink.forPage(null).length, 1);
        expect(again.ink.forPage(page.id).single.samples, line());
      },
    );

    test('undo takes a stroke away, redo brings it back', () async {
      final s = await opened();
      s.addInk(
        pageId: s.controller.scene.value.cards.first.id,
        samples: line(),
        width: 2,
        color: 0xFF000000,
      );
      await s.settled();
      await s.undo();
      expect(s.ink.count, 0);
      expect(await storedInk(), isEmpty);
      await s.redo();
      expect(s.ink.count, 1);
      expect((await storedInk()).length, 1);
    });

    test('a failed save takes the stroke back off the page', () async {
      final flaky = FlakyStore(store);
      final controller = CanvasController(scene: const Scene([]))
        ..viewport = const Size(1000, 800);
      addTearDown(controller.dispose);
      final s = DocumentSession(
        docId: docId,
        store: flaky,
        db: db,
        controller: controller,
        clock: HlcClock('dev', now: () => 8000 + clockTick++),
        ids: SequentialIdGenerator('k${clockTick++}'),
      );
      addTearDown(s.dispose);
      await s.load();
      flaky.failCommits = true;
      s.addInk(
        pageId: controller.scene.value.cards.first.id,
        samples: line(),
        width: 2,
        color: 0xFF000000,
      );
      expect(s.ink.count, 1);
      await s.settled();
      expect(s.ink.count, 0);
      expect(await storedInk(), isEmpty);
    });

    test('leaving right after a stroke still saves it', () async {
      final s = await opened();
      s.addInk(
        pageId: s.controller.scene.value.cards.first.id,
        samples: line(),
        width: 2,
        color: 0xFF000000,
      );
      await s.dispose();
      expect((await storedInk()).length, 1);
    });

    test('highlights and ink live side by side and undo in order', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      s.addInk(pageId: page.id, samples: line(), width: 2, color: 0xFF000000);
      s.addHighlight(
        pageId: page.id,
        selection: TextSelector.between(layoutText(['the quick brown']), 0, 0)!,
        meaning: Meaning.claim,
      );
      await s.settled();
      expect(s.ink.count, 1);
      expect(s.highlights.count, 1);
      await s.undo();
      expect(s.highlights.count, 0);
      expect(s.ink.count, 1, reason: 'undo takes only the last action');
      await s.undo();
      expect(s.ink.count, 0);
    });
  });

  group('erase', () {
    Float32List line() => Float32List.fromList([0, 100, 0.5, 200, 100, 0.5]);

    Future<DocumentSession> opened() async {
      final s = open();
      await s.load();
      return s;
    }

    Future<Set<String>> storedIds() async => {
      for (final e in await store.entities(kind: EntityKind.mark, docId: docId))
        e.id,
    };

    test('one erase is one undo step that brings everything back', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      final a = s.addInk(pageId: page.id, samples: line(), width: 2, color: 1);
      final b = s.addInk(pageId: page.id, samples: line(), width: 2, color: 2);
      await s.settled();
      expect(await storedIds(), {a, b});

      // The tool has already taken both off the page; it asks to save that.
      s.ink.remove(a);
      s.ink.remove(b);
      s.commitErase(deleted: {a, b}, created: const []);
      await s.settled();
      expect(await storedIds(), isEmpty);
      expect(s.bus.undoLabel, 'Erase');

      await s.undo();
      expect(s.ink.count, 2, reason: 'one undo restores the whole wipe');
      expect(await storedIds(), {a, b});
      await s.redo();
      expect(s.ink.count, 0);
      expect(await storedIds(), isEmpty);
    });

    test('a partial erase saves the pieces and deletes the original', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      final a = s.addInk(pageId: page.id, samples: line(), width: 2, color: 1);
      await s.settled();
      final p1 = Ink(
        id: s.newId(),
        docId: docId,
        pageId: page.id,
        samples: Float32List.fromList([0, 100, 0.5, 80, 100, 0.5]),
        width: 2,
        color: 1,
      );
      final p2 = Ink(
        id: s.newId(),
        docId: docId,
        pageId: page.id,
        samples: Float32List.fromList([120, 100, 0.5, 200, 100, 0.5]),
        width: 2,
        color: 1,
      );
      s.ink.remove(a);
      s.ink.add(p1);
      s.ink.add(p2);
      s.commitErase(deleted: {a}, created: [p1, p2]);
      await s.settled();
      expect(await storedIds(), {p1.id, p2.id});
      // They survive a reopen.
      final again = await opened();
      expect(again.ink.count, 2);

      await s.undo();
      expect(await storedIds(), {
        a,
      }, reason: 'the original is back, pieces gone');
      expect(s.ink.byId(a), isNotNull);
      expect(s.ink.byId(p1.id), isNull);
    });

    test('a highlight and a stroke erased together undo together', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first;
      final ink = s.addInk(
        pageId: page.id,
        samples: line(),
        width: 2,
        color: 1,
      );
      final h = s.addHighlight(
        pageId: page.id,
        selection: TextSelector.between(layoutText(['the quick']), 0, 0)!,
        meaning: Meaning.claim,
      );
      await s.settled();
      s.ink.remove(ink);
      s.highlights.remove(h);
      s.commitErase(deleted: {ink, h}, created: const []);
      await s.settled();
      expect(await storedIds(), isEmpty);
      await s.undo();
      expect(s.ink.count, 1);
      expect(s.highlights.count, 1);
    });

    test('a failed save puts the page back as it really is', () async {
      final flaky = FlakyStore(store);
      final controller = CanvasController(scene: const Scene([]))
        ..viewport = const Size(1000, 800);
      addTearDown(controller.dispose);
      final s = DocumentSession(
        docId: docId,
        store: flaky,
        db: db,
        controller: controller,
        clock: HlcClock('dev', now: () => 9000 + clockTick++),
        ids: SequentialIdGenerator('e${clockTick++}'),
      );
      addTearDown(s.dispose);
      await s.load();
      final a = s.addInk(
        pageId: controller.scene.value.cards.first.id,
        samples: line(),
        width: 2,
        color: 1,
      );
      await s.settled();
      flaky.failCommits = true;
      s.ink.remove(a);
      s.commitErase(deleted: {a}, created: const []);
      await s.settled();
      expect(s.ink.byId(a), isNotNull, reason: 'it was never really erased');
    });
  });

  group('notes', () {
    Future<DocumentSession> opened() async {
      final s = open();
      await s.load();
      return s;
    }

    Future<List<Note>> storedNotes() async => [
      for (final e in await store.entities(kind: EntityKind.mark, docId: docId))
        if (Mark.fromState(e) case final Note n) n,
    ];

    Future<void> pause([int ms = 80]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    test(
      'placing a note makes an empty draft and asks for the keyboard',
      () async {
        final s = await opened();
        final page = s.controller.scene.value.cards.first;
        final id = s.beginNote(pageId: page.id, x: 30, y: 40);
        expect(s.notes.isDraft(id), isTrue);
        expect(s.notes.focusId, id);
        expect(s.notes.byId(id)!.text, '');
        await s.settled();
        expect(await storedNotes(), isEmpty, reason: 'nothing is saved yet');
        expect(s.bus.canUndo, isFalse);
      },
    );

    test('an empty note that loses focus vanishes without a trace', () async {
      final s = await opened();
      final id = s.beginNote(x: 5, y: 5);
      await s.noteBlurred(id);
      expect(s.notes.byId(id), isNull);
      await s.settled();
      expect(await storedNotes(), isEmpty);
      expect(
        s.bus.canUndo,
        isFalse,
        reason: 'no undo step for a discarded draft',
      );
    });

    test('typing is saved once, when typing pauses', () async {
      final s = await opened();
      final id = s.beginNote(
        pageId: s.controller.scene.value.cards.first.id,
        x: 30,
        y: 40,
      );
      s.editNoteText(id, 'W');
      s.editNoteText(id, 'Why');
      s.editNoteText(id, 'Why 3%?');
      expect(await storedNotes(), isEmpty, reason: 'still typing');
      await pause();
      await s.settled();
      final saved = (await storedNotes()).single;
      expect(saved.text, 'Why 3%?');
      expect((saved.x, saved.y), (30.0, 40.0));
      expect(s.notes.isDraft(id), isFalse);
      expect(s.bus.undoDepth, 1, reason: 'one burst of typing, one step');
      expect(s.bus.undoLabel, 'Note');
    });

    test('losing focus saves at once, without waiting for the pause', () async {
      final s = await opened();
      final id = s.beginNote(x: 5, y: 5);
      s.editNoteText(id, 'quick');
      await s.noteBlurred(id);
      expect((await storedNotes()).single.text, 'quick');
    });

    test(
      'later edits are separate steps; undo goes back one at a time',
      () async {
        final s = await opened();
        final id = s.beginNote(x: 5, y: 5);
        s.editNoteText(id, 'one');
        await s.noteBlurred(id);
        s.editNoteText(id, 'one two');
        await pause();
        await s.settled();
        expect((await storedNotes()).single.text, 'one two');
        expect(s.bus.undoLabel, 'Edit note');
        await s.undo();
        expect(s.notes.byId(id)!.text, 'one');
        expect((await storedNotes()).single.text, 'one');
        await s.undo();
        expect(s.notes.byId(id), isNull, reason: 'the creation is undone too');
        expect(await storedNotes(), isEmpty);
      },
    );

    test(
      'moving and resizing save as one step at the end of the drag',
      () async {
        final s = await opened();
        final id = s.beginNote(x: 5, y: 5);
        s.editNoteText(id, 'hi');
        await s.noteBlurred(id);
        final before = s.bus.undoDepth;
        for (var i = 1; i <= 10; i++) {
          s.noteGeometryChanged(id, x: 5.0 + i * 3, y: 5.0 + i);
        }
        expect(s.notes.byId(id)!.x, 35, reason: 'shows at once');
        expect((await storedNotes()).single.x, 5, reason: 'not saved mid-drag');
        await s.noteGeometryDone(id);
        expect((await storedNotes()).single.x, 35);
        expect(s.bus.undoDepth, before + 1);
        s.noteGeometryChanged(id, width: 300, height: 200);
        await s.noteGeometryDone(id);
        final n = (await storedNotes()).single;
        expect((n.width, n.height), (300.0, 200.0));
        await s.undo();
        expect((await storedNotes()).single.width, Note.defaultWidth);
      },
    );

    test('moving a draft that has no text saves nothing', () async {
      final s = await opened();
      final id = s.beginNote(x: 5, y: 5);
      s.noteGeometryChanged(id, x: 50);
      await s.noteGeometryDone(id);
      await s.settled();
      expect(await storedNotes(), isEmpty);
    });

    test(
      'delete is undoable, and a saved note emptied then blurred is deleted',
      () async {
        final s = await opened();
        final a = s.beginNote(x: 5, y: 5);
        s.editNoteText(a, 'keep me');
        await s.noteBlurred(a);
        s.deleteNote(a);
        await s.settled();
        expect(await storedNotes(), isEmpty);
        await s.undo();
        expect((await storedNotes()).single.text, 'keep me');
        expect(s.notes.byId(a), isNotNull);

        s.editNoteText(a, '');
        await s.noteBlurred(a);
        await s.settled();
        expect(await storedNotes(), isEmpty, reason: 'emptied, then discarded');
        await s.undo();
        expect((await storedNotes()).single.text, 'keep me');
      },
    );

    test(
      'notes come back when the document is reopened, free ones too',
      () async {
        final s = await opened();
        final page = s.controller.scene.value.cards.first;
        final a = s.beginNote(pageId: page.id, x: 1, y: 2);
        s.editNoteText(a, 'on page');
        final b = s.beginNote(x: 300, y: 400);
        s.editNoteText(b, 'free');
        await s.noteBlurred(a);
        await s.noteBlurred(b);
        final again = await opened();
        expect(again.notes.count, 2);
        expect(again.notes.forPage(page.id).single.text, 'on page');
        expect(again.notes.forPage(null).single.text, 'free');
      },
    );

    test(
      'leaving the screen right after typing still saves the text',
      () async {
        final s = open(noteDelay: const Duration(seconds: 5));
        await s.load();
        final id = s.beginNote(x: 5, y: 5);
        s.editNoteText(id, 'typed just now');
        await s.dispose();
        expect((await storedNotes()).single.text, 'typed just now');
      },
    );

    test('an undo elsewhere does not lose a draft being typed into', () async {
      final s = await opened();
      s.addInk(
        pageId: s.controller.scene.value.cards.first.id,
        samples: Float32List.fromList([0, 0, 1, 9, 9, 1]),
        width: 2,
        color: 1,
      );
      await s.settled();
      final id = s.beginNote(x: 5, y: 5);
      s.editNoteText(id, 'typing');
      await s.undo(); // takes back the ink
      expect(s.notes.byId(id)?.text, 'typing');
    });
  });

  group('links', () {
    final text = layoutText(['the quick brown', 'fox jumps over.']);

    Future<DocumentSession> opened() async {
      final s = open();
      await s.load();
      return s;
    }

    Future<Set<String>> storedLinks() async => {
      for (final e in await store.entities(kind: EntityKind.link, docId: docId))
        e.id,
    };

    /// A saved note and a highlight to link.
    Future<({DocumentSession s, String note, String hl, String page})>
    setup() async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first.id;
      final note = s.beginNote(pageId: page, x: 300, y: 300);
      s.editNoteText(note, 'why?');
      await s.noteBlurred(note);
      final hl = s.addHighlight(
        pageId: page,
        selection: TextSelector.between(text, 1, 1)!,
        meaning: Meaning.claim,
        text: text,
      );
      await s.settled();
      return (s: s, note: note, hl: hl, page: page);
    }

    test('a link is saved, undoable, and survives a reopen', () async {
      final x = await setup();
      x.s.addLink(x.note, x.hl);
      expect(x.s.links.count, 1, reason: 'shows at once');
      await x.s.settled();
      expect((await storedLinks()).length, 1);
      expect(x.s.bus.undoLabel, 'Link');
      final again = await opened();
      expect(again.links.count, 1);
      expect(again.links.all.single.fromNoteId, x.note);
      await x.s.undo();
      expect(x.s.links.count, 0);
      expect(await storedLinks(), isEmpty);
      await x.s.redo();
      expect(x.s.links.count, 1);
    });

    test(
      'the same pair is linked once; a note can link many highlights',
      () async {
        final x = await setup();
        final h2 = x.s.addHighlight(
          pageId: x.page,
          selection: TextSelector.between(text, 3, 3)!,
          meaning: Meaning.method,
          text: text,
        );
        x.s.addLink(x.note, x.hl);
        x.s.addLink(x.note, x.hl);
        x.s.addLink(x.note, h2);
        await x.s.settled();
        expect(x.s.links.count, 2);
        expect((await storedLinks()).length, 2);
      },
    );

    test('a link needs both ends to exist', () async {
      final x = await setup();
      x.s.addLink('no-note', x.hl);
      x.s.addLink(x.note, 'no-highlight');
      expect(x.s.links.count, 0);
    });

    test('removing a link is undoable', () async {
      final x = await setup();
      x.s.addLink(x.note, x.hl);
      await x.s.settled();
      final id = x.s.links.all.single.id;
      x.s.deleteLink(id);
      expect(x.s.links.count, 0);
      await x.s.settled();
      expect(await storedLinks(), isEmpty);
      await x.s.undo();
      expect(x.s.links.count, 1);
      expect((await storedLinks()).length, 1);
    });

    test(
      'deleting the note takes its links, and one undo brings both back',
      () async {
        final x = await setup();
        x.s.addLink(x.note, x.hl);
        await x.s.settled();
        x.s.deleteNote(x.note);
        expect(
          x.s.links.count,
          0,
          reason: 'a link to nothing is not left behind',
        );
        await x.s.settled();
        expect(await storedLinks(), isEmpty);
        await x.s.undo();
        expect(x.s.notes.byId(x.note), isNotNull);
        expect(x.s.links.count, 1);
      },
    );

    test('deleting the highlight takes its links too', () async {
      final x = await setup();
      x.s.addLink(x.note, x.hl);
      await x.s.settled();
      x.s.deleteHighlight(x.hl);
      expect(x.s.links.count, 0);
      await x.s.settled();
      expect(await storedLinks(), isEmpty);
      await x.s.undo();
      expect(x.s.highlights.byId(x.hl), isNotNull);
      expect(x.s.links.count, 1);
    });

    test('erasing the highlight takes its links in the same step', () async {
      final x = await setup();
      x.s.addLink(x.note, x.hl);
      await x.s.settled();
      x.s.highlights.remove(x.hl); // what the eraser tool does first
      x.s.commitErase(deleted: {x.hl}, created: const []);
      expect(x.s.links.count, 0);
      await x.s.settled();
      expect(await storedLinks(), isEmpty);
      await x.s.undo();
      expect(x.s.links.count, 1);
      expect(x.s.highlights.byId(x.hl), isNotNull);
    });

    test(
      'widening a word to its sentence keeps the link on the sentence',
      () async {
        final x = await setup();
        x.s.addLink(x.note, x.hl);
        await x.s.settled();
        final sentence = x.s.replaceHighlight(
          oldId: x.hl,
          pageId: x.page,
          selection: TextSelector.sentenceAt(text, 1)!,
          meaning: Meaning.claim,
          text: text,
        );
        expect(x.s.links.all.single.toHighlightId, sentence);
        await x.s.settled();
        final again = await opened();
        expect(again.links.all.single.toHighlightId, sentence);
        await x.s.undo();
        expect(
          x.s.links.all.single.toHighlightId,
          x.hl,
          reason: 'undo moves it back',
        );
      },
    );

    test('a note still being typed is saved before it is linked', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first.id;
      final hl = s.addHighlight(
        pageId: page,
        selection: TextSelector.between(text, 1, 1)!,
        meaning: Meaning.claim,
        text: text,
      );
      final note = s.beginNote(pageId: page, x: 5, y: 5);
      s.editNoteText(note, 'just typed');
      s.addLink(note, hl);
      await s.settled();
      expect(
        (await store.entities(
          kind: EntityKind.mark,
          docId: docId,
        )).where((e) => e.field<String>(F.type) == 'note').length,
        1,
      );
      expect((await storedLinks()).length, 1);
    });

    test('an empty draft cannot be linked', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first.id;
      final hl = s.addHighlight(
        pageId: page,
        selection: TextSelector.between(text, 1, 1)!,
        meaning: Meaning.claim,
        text: text,
      );
      final note = s.beginNote(pageId: page, x: 5, y: 5);
      s.addLink(note, hl);
      expect(s.links.count, 0);
    });
  });

  group('selection edits', () {
    final text = layoutText(['the quick brown', 'fox jumps over.']);
    Float32List line([double y = 100]) =>
        Float32List.fromList([10, y, 0.5, 90, y, 0.5]);

    Future<DocumentSession> opened() async {
      final s = open();
      await s.load();
      return s;
    }

    Future<Set<String>> storedIds() async => {
      for (final e in await store.entities(kind: EntityKind.mark, docId: docId))
        e.id,
    };

    test('a move saves the new place of ink and notes as one step', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first.id;
      final i = s.addInk(pageId: page, samples: line(), width: 2, color: 1);
      final n = s.beginNote(pageId: page, x: 5, y: 5);
      s.editNoteText(n, 'hi');
      await s.noteBlurred(n);
      await s.settled();
      final depth = s.bus.undoDepth;
      s.ink.add(s.ink.byId(i)!.translated(30, 10));
      s.notes.update(s.notes.byId(n)!.copyWith(x: 35, y: 15));
      s.commitMove([s.ink.byId(i)!, s.notes.byId(n)!]);
      await s.settled();
      expect(s.bus.undoDepth, depth + 1);
      expect(s.bus.undoLabel, 'Move');
      final again = await opened();
      expect(again.ink.byId(i)!.samples[0], 40);
      expect(again.notes.byId(n)!.x, 35);
      await s.undo();
      expect(s.ink.byId(i)!.samples[0], 10, reason: 'one undo moves both back');
      expect(s.notes.byId(n)!.x, 5);
    });

    test(
      'recoloring changes highlight meaning and ink colour in one step',
      () async {
        final s = await opened();
        final page = s.controller.scene.value.cards.first.id;
        final i = s.addInk(
          pageId: page,
          samples: line(),
          width: 2,
          color: 0xFF000000,
        );
        final h = s.addHighlight(
          pageId: page,
          selection: TextSelector.between(text, 1, 1)!,
          meaning: Meaning.claim,
          text: text,
        );
        await s.settled();
        s.recolorMarks(
          [MarkRef(MarkKind.ink, i), MarkRef(MarkKind.highlight, h)],
          meaning: Meaning.question,
          inkColor: 0xFFF4877E,
        );
        expect(s.highlights.byId(h)!.meaning, Meaning.question);
        expect(s.ink.byId(i)!.color, 0xFFF4877E);
        await s.settled();
        expect(s.bus.undoLabel, 'Recolor');
        final again = await opened();
        expect(again.highlights.byId(h)!.meaning, Meaning.question);
        expect(again.ink.byId(i)!.color, 0xFFF4877E);
        await s.undo();
        expect(s.highlights.byId(h)!.meaning, Meaning.claim);
        expect(s.ink.byId(i)!.color, 0xFF000000);
      },
    );

    test('recoloring to what it already is saves nothing', () async {
      final s = await opened();
      final h = s.addHighlight(
        pageId: s.controller.scene.value.cards.first.id,
        selection: TextSelector.between(text, 1, 1)!,
        meaning: Meaning.claim,
        text: text,
      );
      await s.settled();
      final depth = s.bus.undoDepth;
      s.recolorMarks([MarkRef(MarkKind.highlight, h)], meaning: Meaning.claim);
      await s.settled();
      expect(s.bus.undoDepth, depth);
    });

    test(
      'deleting a mixed selection is one step, with links, and undoes whole',
      () async {
        final s = await opened();
        final page = s.controller.scene.value.cards.first.id;
        final i = s.addInk(pageId: page, samples: line(), width: 2, color: 1);
        final h = s.addHighlight(
          pageId: page,
          selection: TextSelector.between(text, 1, 1)!,
          meaning: Meaning.claim,
          text: text,
        );
        final n = s.beginNote(pageId: page, x: 5, y: 5);
        s.editNoteText(n, 'note');
        await s.noteBlurred(n);
        s.addLink(n, h);
        await s.settled();
        final depth = s.bus.undoDepth;
        s.deleteMarks([
          MarkRef(MarkKind.ink, i),
          MarkRef(MarkKind.highlight, h),
          MarkRef(MarkKind.note, n),
        ]);
        expect(
          s.ink.count + s.highlights.count + s.notes.count + s.links.count,
          0,
        );
        await s.settled();
        expect(await storedIds(), isEmpty);
        expect(
          await store.entities(kind: EntityKind.link, docId: docId),
          isEmpty,
        );
        expect(s.bus.undoDepth, depth + 1);
        await s.undo();
        expect(await storedIds(), {i, h, n});
        expect(s.links.count, 1);
      },
    );

    test('deleting marks that are not there is quietly nothing', () async {
      final s = await opened();
      final depth = s.bus.undoDepth;
      s.deleteMarks([const MarkRef(MarkKind.ink, 'nope')]);
      await s.settled();
      expect(s.bus.undoDepth, depth);
    });

    test('Add note on a highlight links the note once it has text', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first.id;
      final h = s.addHighlight(
        pageId: page,
        selection: TextSelector.between(text, 1, 1)!,
        meaning: Meaning.claim,
        text: text,
      );
      final n = s.beginNote(pageId: page, x: 5, y: 5, linkToHighlight: h);
      expect(s.links.count, 0, reason: 'nothing to link yet');
      s.editNoteText(n, 'my thought');
      await s.noteBlurred(n);
      await s.settled();
      expect(s.links.count, 1);
      expect(s.links.all.single.toHighlightId, h);
      expect(
        (await store.entities(kind: EntityKind.link, docId: docId)).length,
        1,
      );
    });

    test('an Add note that is left empty leaves no link', () async {
      final s = await opened();
      final page = s.controller.scene.value.cards.first.id;
      final h = s.addHighlight(
        pageId: page,
        selection: TextSelector.between(text, 1, 1)!,
        meaning: Meaning.claim,
        text: text,
      );
      final n = s.beginNote(pageId: page, x: 5, y: 5, linkToHighlight: h);
      await s.noteBlurred(n);
      await s.settled();
      expect(s.links.count, 0);
      expect(s.notes.count, 0);
    });
  });
}
