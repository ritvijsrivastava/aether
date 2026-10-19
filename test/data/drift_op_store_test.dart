import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/domain/commands/command.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/ops/entity_state.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AetherDatabase memDb() => AetherDatabase(NativeDatabase.memory());

Future<Map<String, EntityState>> byId(DriftOpStore s) async => {
  for (final e in await s.entities(includeDeleted: true)) e.id: e,
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AetherDatabase db;
  late DriftOpStore store;
  setUp(() {
    db = memDb();
    store = DriftOpStore(db);
  });
  tearDown(() => db.close());

  CommandBus bus0() {
    var t = 1000;
    return CommandBus(
      store: store,
      clock: HlcClock('dev1', now: () => t++),
      ids: SequentialIdGenerator('x'),
    );
  }

  test('commit writes the log and the snapshot together', () async {
    final bus = bus0();
    const note = Note(
      id: 'n1',
      docId: 'd1',
      pageId: 'p1',
      x: 3,
      y: 4,
      text: 'hello',
    );
    await bus.run(
      CommandFactory(store).create(EntityKind.mark, 'n1', note.toFields()),
    );
    expect((await store.allOps()).length, note.toFields().length + 1);
    final e = (await store.entity('n1'))!;
    expect(Mark.fromState(e), isA<Note>());
    expect(e.fields['text'], 'hello');
  });

  test('indexed columns mirror well-known fields', () async {
    final bus = bus0();
    const n = Note(id: 'n1', docId: 'd1', pageId: 'p1', x: 10, y: 20);
    await bus.run(
      CommandFactory(store).create(EntityKind.mark, 'n1', n.toFields()),
    );
    final row = await (db.select(
      db.entities,
    )..where((e) => e.id.equals('n1'))).getSingle();
    expect((row.docId, row.pageId, row.markType), ('d1', 'p1', 'note'));
    expect((row.bx0, row.by0, row.bx1), (10.0, 20.0, 230.0));
  });

  test('entities() filters by kind, document and deletion', () async {
    final bus = bus0();
    final f = CommandFactory(store);
    await bus.run(f.create(EntityKind.document, 'd1', {'title': 'A'}));
    await bus.run(
      f.create(EntityKind.mark, 'm1', {'type': 'note', 'docId': 'd1'}),
    );
    await bus.run(
      f.create(EntityKind.mark, 'm2', {'type': 'note', 'docId': 'd2'}),
    );
    await bus.run(await f.delete('m1'));
    expect((await store.entities(kind: EntityKind.mark, docId: 'd1')), isEmpty);
    expect(
      (await store.entities(
        kind: EntityKind.mark,
        docId: 'd1',
        includeDeleted: true,
      )).length,
      1,
    );
    expect((await store.entities(kind: EntityKind.mark)).map((e) => e.id), [
      'm2',
    ]);
    expect((await store.entities(kind: EntityKind.document)).map((e) => e.id), [
      'd1',
    ]);
  });

  test('replaying a commit is harmless (idempotent log)', () async {
    final op = Op(
      opId: 'o1',
      hlc: const Hlc(5, 0, 'd'),
      entityKind: EntityKind.mark,
      entityId: 'm',
      kind: OpKind.setField,
      txGroupId: 't',
      field: 'x',
      value: 1,
    );
    await store.commit([op]);
    await store.commit([op]);
    expect((await store.allOps()).length, 1);
    expect((await store.entity('m'))!.fields['x'], 1);
  });

  test(
    'snapshot equals a rebuild from the log after random activity',
    () async {
      for (var seed = 0; seed < 5; seed++) {
        final d = memDb();
        final s = DriftOpStore(d);
        var t = 1;
        final bus = CommandBus(
          store: s,
          clock: HlcClock('dev1', now: () => t++),
          ids: SequentialIdGenerator('s$seed'),
        );
        final f = CommandFactory(s);
        final rnd = Random(seed);
        final ids = <String>[];
        for (var i = 0; i < 60; i++) {
          final k = rnd.nextInt(6);
          if (ids.isEmpty || k == 0) {
            ids.add('m${ids.length}');
            await bus.run(
              f.create(EntityKind.mark, ids.last, {
                'type': 'note',
                'docId': 'd',
                'x': rnd.nextInt(99).toDouble(),
                'bx0': 1.0,
              }),
            );
          } else if (k == 1) {
            await bus.run(await f.delete(ids[rnd.nextInt(ids.length)]));
          } else if (k == 2) {
            await bus.undo();
          } else if (k == 3) {
            await bus.redo();
          } else {
            await bus.run(
              await f.setFields(ids[rnd.nextInt(ids.length)], {
                'x': rnd.nextInt(99).toDouble(),
              }),
            );
          }
        }
        final live = await byId(s);
        await s.rebuildSnapshots();
        expect(await byId(s), live, reason: 'seed $seed');
        await d.close();
      }
    },
  );

  test(
    'a failure inside a transaction leaves neither log nor snapshot behind',
    () async {
      final op = Op(
        opId: 'o1',
        hlc: const Hlc(5, 0, 'd'),
        entityKind: EntityKind.mark,
        entityId: 'm',
        kind: OpKind.create,
        txGroupId: 't',
      );
      await expectLater(
        db.transaction(() async {
          await store.commit([op]);
          throw StateError('simulated crash before commit');
        }),
        throwsStateError,
      );
      expect(await store.allOps(), isEmpty);
      expect(await store.entity('m'), isNull);
    },
  );

  test(
    'data survives closing and reopening the file; deviceId is stable',
    () async {
      final dir = await Directory.systemTemp.createTemp('aether_db_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/t.db');

      var d = AetherDatabase(openDatabaseFile(file));
      final id1 = await d.deviceId();
      final s1 = DriftOpStore(d);
      await s1.commit([
        Op(
          opId: 'o1',
          hlc: const Hlc(5, 0, 'd'),
          entityKind: EntityKind.mark,
          entityId: 'm',
          kind: OpKind.create,
          txGroupId: 't',
        ),
        Op(
          opId: 'o2',
          hlc: const Hlc(6, 0, 'd'),
          entityKind: EntityKind.mark,
          entityId: 'm',
          kind: OpKind.setField,
          txGroupId: 't',
          field: 'text',
          value: 'kept',
        ),
      ]);
      await d.putSetting('theme', 'dark');
      await d.close();

      d = AetherDatabase(openDatabaseFile(file));
      addTearDown(d.close);
      final s2 = DriftOpStore(d);
      expect((await s2.entity('m'))!.fields['text'], 'kept');
      expect((await s2.allOps()).length, 2);
      expect(await d.deviceId(), id1);
      expect((await d.select(d.device).get()).length, 1);
      expect(await d.setting('theme'), 'dark');
    },
  );

  test('ink payload round-trips through the database', () async {
    final bus = bus0();
    final ink = Ink(
      id: 'i1',
      docId: 'd1',
      pageId: 'p1',
      samples: Float32List.fromList([1, 2, .5, 3, 4, .6, 5, 6, .7]),
    );
    await bus.run(
      CommandFactory(store).create(EntityKind.mark, 'i1', ink.toFields()),
    );
    final back = Mark.fromState((await store.entity('i1'))!) as Ink;
    expect(back.samples, ink.samples);
  });
}
