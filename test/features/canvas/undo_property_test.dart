import 'dart:io';
import 'dart:convert' show jsonEncode;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/domain/commands/command.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:aether/features/canvas/document_session.dart';
import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/select/selection.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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

  DocumentSession open() {
    final controller = CanvasController()..viewport = const Size(1000, 800);
    addTearDown(controller.dispose);
    final s = DocumentSession(
      docId: docId,
      store: store,
      db: db,
      controller: controller,
      clock: HlcClock('dev', now: () => 5000 + tick++),
      ids: SequentialIdGenerator('s${tick++}'),
    );
    addTearDown(s.dispose);
    return s;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aether_undoprop_');
    db = AetherDatabase(NativeDatabase.memory());
    store = DriftOpStore(db);
    var t = 1000;
    final bus = CommandBus(
      store: store,
      clock: HlcClock('seed', now: () => t++),
      ids: SequentialIdGenerator('seed'),
    );
    final f = CommandFactory(store);
    docId = 'board';
    await bus.run(
      f.create(EntityKind.document, docId, {
        'title': 'Undo property board',
      }, label: 'New board'),
    );
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  /// The stored marks and links, as one canonical string: what a reopen would
  /// show. Deleted entities are not in it.
  Future<String> stored() async {
    final rows = <String>[];
    for (final kind in [EntityKind.mark]) {
      for (final e in await store.entities(kind: kind, docId: docId)) {
        final f = Map<String, Object?>.from(e.fields);
        rows.add('${e.id}|${jsonEncode(f, toEncodable: (o) => o.toString())}');
      }
    }
    rows.sort();
    return rows.join('\n');
  }

  /// What is on the page, as a string, from the in-memory layers.
  String onPage(DocumentSession s) {
    final rows = <String>[
      for (final i in s.ink.all) 'i|${i.id}|${i.color}|${i.samples.join(",")}',
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
    String addStroke() {
      s.addInk(
        samples: stroke(r),
        width: 1 + r.nextInt(6).toDouble(),
        color: 0xFF000000 + r.nextInt(4),
      );
      return 'addInk';
    }

    final inks = s.ink.all.toList();
    const weights = [0, 0, 2, 2, 2, 2, 2, 3, 3, 3, 3, 4, 5, 5, 5, 5, 5, 5, 6];
    switch (weights[r.nextInt(weights.length)]) {
      case 0:
        s.addInk(
          samples: stroke(r),
          width: 1 + r.nextInt(6).toDouble(),
          color: 0xFF000000 + r.nextInt(4),
        );
        return 'addInk';
      case 2:
        if (inks.isEmpty) return addStroke();
        final refs = <MarkRef>[
          for (final i in inks)
            if (r.nextBool()) MarkRef(MarkKind.ink, i.id),
        ];
        if (refs.isEmpty) return addStroke();
        s.deleteMarks(refs);
        return 'deleteMarks';
      case 3:
        if (inks.isEmpty) return addStroke();
        final i = inks[r.nextInt(inks.length)];
        s.ink.add(
          i.translated(r.nextDouble() * 40 - 20, r.nextDouble() * 40 - 20),
        );
        s.commitMove([s.ink.byId(i.id)!]);
        return 'moveInk';
      case 4:
        if (inks.isEmpty) return addStroke();
        s.recolorMarks([
          for (final i in inks) MarkRef(MarkKind.ink, i.id),
        ], inkColor: 0xFF000000 + r.nextInt(4));
        return 'recolor';
      case 5:
        // A partial erase of one stroke into two pieces.
        if (inks.isEmpty) return addStroke();
        final i = inks[r.nextInt(inks.length)];
        final pieces = <Ink>[
          Ink(
            id: s.newId(),
            docId: docId,
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
      default:
        return addStroke();
    }
  }

  for (final seed in List.generate(12, (i) => i + 1)) {
    test(
      'a random session of 40 edits (seed $seed): undo and redo retrace it exactly',
      () async {
        final r = math.Random(seed);
        final s = open();
        await s.load();

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
        final top = s.bus.undoDepth;
        final finalStored = await stored();
        final finalPage = onPage(s);
        expect(top, greaterThan(5), reason: 'the session did real work');

        // The page and storage agree at every step (what is shown is what a
        // reopen would show).
        final reopened = open();
        await reopened.load();
        expect(onPage(reopened), finalPage, reason: 'a reopen shows the same');

        // Walk all the way back, checking each state we recorded.
        for (var d = top - 1; d >= 0; d--) {
          await s.undo();
          await s.settled();
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
        expect(s.ink.count, 0);

        // And forward again.
        for (var d = 1; d <= top; d++) {
          await s.redo();
          await s.settled();
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
      s.addInk(samples: stroke(r), width: 2, color: 1);
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
