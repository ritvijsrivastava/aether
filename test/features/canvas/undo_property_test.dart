import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/data/pdf/pdf_storage.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:aether/domain/text/page_text.dart';
import 'package:aether/domain/text/text_selection.dart';
import 'package:aether/features/canvas/document_session.dart';
import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/select/selection.dart';
import 'package:aether/features/library/import/pdf_importer.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// Undo and redo are the heart of "never lose a mark" (SPEC 9.3). These tests
/// run long random sessions of every kind of edit and check, after every step,
/// that going back and forth through history reproduces exactly the states
/// that were there.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late AetherDatabase db;
  late DriftOpStore store;
  late String docId;
  var tick = 0;

  final text = () {
    final codes = <int>[];
    final boxes = <double>[];
    const lines = [
      'the quick brown fox',
      'jumps over the lazy dog.',
      'Then it sat down.',
    ];
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
    return PageText.build(
      Int32List.fromList(codes),
      Float32List.fromList(boxes),
    );
  }();

  DocumentSession open() {
    final controller = CanvasController(scene: const Scene([]))
      ..viewport = const Size(1000, 800);
    addTearDown(controller.dispose);
    final s = DocumentSession(
      docId: docId,
      store: store,
      db: db,
      controller: controller,
      clock: HlcClock('dev', now: () => 5000 + tick++),
      ids: SequentialIdGenerator('s${tick++}'),
      noteEditDelay: const Duration(milliseconds: 5),
    );
    addTearDown(s.dispose);
    return s;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aether_undoprop_');
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

  /// The stored marks and links, as one canonical string: what a reopen would
  /// show. Deleted entities are not in it.
  Future<String> stored() async {
    final rows = <String>[];
    for (final kind in [EntityKind.mark, EntityKind.link]) {
      for (final e in await store.entities(kind: kind, docId: docId)) {
        final f = Map<String, Object?>.from(e.fields);
        rows.add('${e.id}|${jsonEncode(f, toEncodable: (o) => o.toString())}');
      }
    }
    rows.sort();
    return rows.join('\n');
  }

  /// A link must always join a note and a highlight that both exist: in
  /// storage, and on the page.
  Future<void> expectNoDanglingLinks(DocumentSession s, String when) async {
    final marks = {
      for (final e in await store.entities(kind: EntityKind.mark, docId: docId))
        e.id,
    };
    for (final e in await store.entities(kind: EntityKind.link, docId: docId)) {
      final l = Link.fromState(e);
      expect(
        marks,
        contains(l.fromNoteId),
        reason: 'stored link $when: its note is gone',
      );
      expect(
        marks,
        contains(l.toHighlightId),
        reason: 'stored link $when: its highlight is gone',
      );
    }
    for (final l in s.links.all) {
      expect(
        s.notes.byId(l.fromNoteId),
        isNotNull,
        reason: 'page link $when: no note',
      );
      expect(
        s.highlights.byId(l.toHighlightId),
        isNotNull,
        reason: 'page link $when: no highlight',
      );
    }
  }

  /// What is on the page, as a string, from the in-memory layers.
  String onPage(DocumentSession s) {
    final rows = <String>[
      for (final h in s.highlights.all)
        'h|${h.id}|${h.color}|${h.startChar}-${h.endChar}|${h.pageId}',
      for (final i in s.ink.all)
        'i|${i.id}|${i.color}|${i.pageId}|${i.samples.join(",")}',
      for (final n in s.notes.all)
        if (!s.notes.isDraft(n.id))
          'n|${n.id}|${n.x}|${n.y}|${n.width}|${n.height}|${n.text}',
      for (final l in s.links.all)
        'l|${l.id}|${l.fromNoteId}|${l.toHighlightId}',
    ]..sort();
    return rows.join('\n');
  }

  Float32List stroke(math.Random r) {
    final x = r.nextDouble() * 400, y = r.nextDouble() * 600;
    return Float32List.fromList([
      x, y, 0.4, //
      x + 10 + r.nextDouble() * 50, y + r.nextDouble() * 20, 0.6,
      x + 70 + r.nextDouble() * 50, y + r.nextDouble() * 40, 0.5,
    ]);
  }

  /// One random edit. Returns its name (for failure messages).
  Future<String> randomEdit(DocumentSession s, math.Random r) async {
    final page = s.controller.scene.value.cards[r.nextInt(3)].id;
    final inks = s.ink.all.toList();
    final hls = s.highlights.all.toList();
    final notes = s.notes.all.where((n) => !s.notes.isDraft(n.id)).toList();
    final links = s.links.all.toList();
    // Weighted so that links, and deleting things that have links, happen a lot.
    const weights = [
      0,
      0,
      2,
      2,
      3,
      3,
      5,
      5,
      5,
      5,
      6,
      7,
      8,
      9,
      9,
      9,
      10,
      11,
      12,
    ];
    switch (weights[r.nextInt(weights.length)]) {
      case 0:
        s.addInk(
          pageId: page,
          samples: stroke(r),
          width: 1 + r.nextInt(6).toDouble(),
          color: 0xFF000000 + r.nextInt(4),
        );
        return 'addInk';
      case 2:
        final a = r.nextInt(text.words.length),
            b = r.nextInt(text.words.length);
        s.addHighlight(
          pageId: page,
          selection: TextSelector.between(text, a, b)!,
          color: Swatch.defaults[r.nextInt(3)],
          text: text,
        );
        return 'addHighlight';
      case 3:
        final id = s.beginNote(
          pageId: page,
          x: r.nextDouble() * 300,
          y: r.nextDouble() * 300,
        );
        s.editNoteText(id, 'note ${r.nextInt(1000)}');
        await s.noteBlurred(id);
        return 'addNote';
      case 5:
        if (notes.isEmpty || hls.isEmpty) return 'skip';
        s.addLink(
          notes[r.nextInt(notes.length)].id,
          hls[r.nextInt(hls.length)].id,
        );
        return 'addLink';
      case 6:
        if (links.isEmpty) return 'skip';
        s.deleteLink(links[r.nextInt(links.length)].id);
        return 'deleteLink';
      case 7:
        if (notes.isEmpty) return 'skip';
        s.deleteNote(notes[r.nextInt(notes.length)].id);
        return 'deleteNote';
      case 8:
        if (hls.isEmpty) return 'skip';
        s.deleteHighlight(hls[r.nextInt(hls.length)].id);
        return 'deleteHighlight';
      case 9:
        if (inks.isEmpty && hls.isEmpty && notes.isEmpty) return 'skip';
        final refs = <MarkRef>[
          for (final i in inks)
            if (r.nextBool()) MarkRef(MarkKind.ink, i.id),
          for (final h in hls)
            if (r.nextBool()) MarkRef(MarkKind.highlight, h.id),
          for (final n in notes)
            if (r.nextBool()) MarkRef(MarkKind.note, n.id),
        ];
        if (refs.isEmpty) return 'skip';
        s.deleteMarks(refs);
        return 'deleteMarks';
      case 10:
        if (inks.isEmpty) return 'skip';
        final i = inks[r.nextInt(inks.length)];
        s.ink.add(
          i.translated(r.nextDouble() * 40 - 20, r.nextDouble() * 40 - 20),
        );
        s.commitMove([s.ink.byId(i.id)!]);
        return 'moveInk';
      case 11:
        if (hls.isEmpty && inks.isEmpty) return 'skip';
        s.recolorMarks(
          [
            for (final h in hls) MarkRef(MarkKind.highlight, h.id),
            for (final i in inks) MarkRef(MarkKind.ink, i.id),
          ],
          highlightColor: Swatch.defaults[r.nextInt(3)],
          inkColor: 0xFF000000 + r.nextInt(4),
        );
        return 'recolor';
      default:
        // A partial erase of one stroke into two pieces.
        if (inks.isEmpty) return 'skip';
        final i = inks[r.nextInt(inks.length)];
        final pieces = <Ink>[
          Ink(
            id: s.newId(),
            docId: docId,
            pageId: i.pageId,
            samples: Float32List.fromList(
              i.samples.sublist(0, 3) + i.samples.sublist(3, 6),
            ),
            width: i.width,
            color: i.color,
          ),
        ];
        s.ink.remove(i.id);
        s.ink.add(pieces.single);
        s.commitErase(deleted: {i.id}, created: pieces);
        return 'partialErase';
    }
  }

  for (final seed in List.generate(12, (i) => i + 1)) {
    test(
      'a random session of 40 edits (seed $seed): undo and redo retrace it exactly',
      () async {
        final r = math.Random(seed);
        final s = open();
        await s.load();
        final cards = s.controller.scene.value.cards;
        expect(cards.length, greaterThanOrEqualTo(3));

        // The state at each depth of the undo stack, from storage and from the
        // page.
        final storedAt = <int, String>{0: await stored()};
        final pageAt = <int, String>{0: onPage(s)};
        final log = <String>[];
        for (var step = 0; step < 40; step++) {
          log.add(await randomEdit(s, r));
          await s.settled();
          final d = s.bus.undoDepth;
          storedAt[d] = await stored();
          pageAt[d] = onPage(s);
          expect(
            onPage(s),
            pageAt[d],
            reason: 'the page matches itself after ${log.join(", ")}',
          );
        }
        await expectNoDanglingLinks(s, 'at the end of the session');
        final top = s.bus.undoDepth;
        final finalStored = await stored();
        final finalPage = onPage(s);
        expect(top, greaterThan(10), reason: 'the session did real work');

        // The page and storage agree at every step (what is shown is what a
        // reopen would show).
        final reopened = open();
        await reopened.load();
        expect(onPage(reopened), finalPage, reason: 'a reopen shows the same');

        // Walk all the way back, checking each state we recorded.
        for (var d = top - 1; d >= 0; d--) {
          await s.undo();
          await s.settled();
          await expectNoDanglingLinks(s, 'undoing to depth $d');
          if (storedAt.containsKey(d)) {
            expect(
              await stored(),
              storedAt[d],
              reason: 'stored, after undoing to depth $d of $top',
            );
            expect(onPage(s), pageAt[d], reason: 'on the page, depth $d');
          }
        }
        expect(
          await stored(),
          storedAt[0],
          reason: 'everything undone is the empty document',
        );
        expect(
          s.ink.count + s.highlights.count + s.notes.count + s.links.count,
          0,
        );

        // And forward again.
        for (var d = 1; d <= top; d++) {
          await s.redo();
          await s.settled();
          await expectNoDanglingLinks(s, 'redoing to depth $d');
          if (storedAt.containsKey(d)) {
            expect(
              await stored(),
              storedAt[d],
              reason: 'stored, after redoing to depth $d',
            );
            expect(onPage(s), pageAt[d], reason: 'on the page, redo depth $d');
          }
        }
        expect(await stored(), finalStored);
        expect(onPage(s), finalPage);
      },
    );
  }

  test(
    'a new edit after undoing clears redo and keeps history sound',
    () async {
      final r = math.Random(99);
      final s = open();
      await s.load();
      for (var i = 0; i < 12; i++) {
        await randomEdit(s, r);
        await s.settled();
      }
      for (var i = 0; i < 4; i++) {
        await s.undo();
      }
      await s.settled();
      final before = await stored();
      s.addInk(
        pageId: s.controller.scene.value.cards.first.id,
        samples: stroke(r),
        width: 2,
        color: 1,
      );
      await s.settled();
      expect(
        s.bus.canRedo,
        isFalse,
        reason: 'the undone steps are gone for good',
      );
      await s.undo();
      await s.settled();
      expect(await stored(), before);
    },
  );
}
