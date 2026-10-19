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
}
