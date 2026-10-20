import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/domain/commands/command.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/ops/entity_state.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/select/selection.dart'
    show MarkKind, MarkRef;
import 'package:aether/domain/ops/op.dart';
import 'package:aether/domain/ops/op_store.dart';
import 'package:aether/features/canvas/document_session.dart';
import 'package:aether/features/canvas/engine/canvas_controller.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
    OpStore? overStore,
    Duration delay = const Duration(milliseconds: 40),
  }) {
    final controller = CanvasController()..viewport = const Size(1000, 800);
    addTearDown(controller.dispose);
    final session = DocumentSession(
      docId: id ?? docId,
      store: overStore ?? store,
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
    var t = 1000;
    final bus = CommandBus(
      store: store,
      clock: HlcClock('seed', now: () => t++),
      ids: SequentialIdGenerator('seed'),
    );
    final factory = CommandFactory(store);
    docId = 'board';
    await bus.run(
      factory.create(EntityKind.document, docId, {
        'title': 'Test board',
      }, label: 'New board'),
    );
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<List<EntityState>> storedInk() async => [
    for (final e in await store.entities(kind: EntityKind.mark, docId: docId))
      if (e.field<String>(F.type) == 'ink') e,
  ];

  group('loading', () {
    test('a missing or deleted document does not open', () async {
      final s = open(id: 'nope');
      expect(await s.load(), isFalse);
    });
  });

  group('ink', () {
    Float32List line([double y = 100]) => Float32List.fromList([
      10, y, 0.4, //
      60, y + 5, 0.6,
      110, y, 0.5,
    ]);

    Future<DocumentSession> opened() async {
      final s = open();
      await s.load();
      return s;
    }

    test('a stroke shows at once and is saved behind it', () async {
      final s = await opened();
      final id = s.addInk(samples: line(), width: 3, color: 0xFFF4877E);
      expect(s.ink.count, 1, reason: 'visible before it is written');
      await s.settled();
      final saved = (await storedInk()).single;
      expect(saved.id, id);
      final back = Mark.fromState(saved) as Ink;
      expect(back.width, 3);
      expect(back.color, 0xFFF4877E);
      expect(back.samples, line());
      expect(s.bus.undoLabel, 'Ink');
    });

    test('strokes come back when the board is reopened', () async {
      final s = await opened();
      s.addInk(samples: line(), width: 2.5, color: 0xFF2B2723);
      s.addInk(samples: line(300), width: 2.5, color: 0xFF2B2723);
      await s.settled();
      final again = await opened();
      expect(again.ink.count, 2);
    });

    test('undo takes a stroke away, redo brings it back', () async {
      final s = await opened();
      s.addInk(samples: line(), width: 2, color: 0xFF000000);
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
      final s = open(overStore: flaky);
      await s.load();
      flaky.failCommits = true;
      s.addInk(samples: line(), width: 2, color: 0xFF000000);
      expect(s.ink.count, 1);
      await s.settled();
      expect(s.ink.count, 0);
      expect(await storedInk(), isEmpty);
    });

    test('leaving right after a stroke still saves it', () async {
      final s = await opened();
      s.addInk(samples: line(), width: 2, color: 0xFF000000);
      await s.dispose();
      expect((await storedInk()).length, 1);
    });
  });

  group('erase', () {
    test('a wipe deletes and creates pieces as one undo step', () async {
      final s = open();
      await s.load();
      s.addInk(
        samples: Float32List.fromList([0, 0, 0.5, 100, 0, 0.5]),
        width: 2,
        color: 0xFF000000,
      );
      await s.settled();
      final firstId = s.ink.all.single.id;
      s.commitErase(
        deleted: {firstId},
        created: [
          Ink(
            id: s.newId(),
            docId: docId,
            samples: Float32List.fromList([0, 0, 0.5, 40, 0, 0.5]),
            width: 2,
            color: 0xFF000000,
          ),
        ],
      );
      await s.settled();
      expect(s.ink.count, 1);
      expect(s.bus.undoLabel, 'Erase');
      await s.undo();
      expect(s.ink.count, 1, reason: 'the original stroke is back');
      expect(s.ink.all.single.id, firstId);
      await s.redo();
      expect(s.ink.count, 1);
    });
  });

  group('selection edits', () {
    Ink stroke(String id, {int color = 0xFF2B2723}) => Ink(
      id: id,
      docId: docId,
      samples: Float32List.fromList([0, 0, 0.5, 10, 10, 0.5]),
      width: 2,
      color: color,
    );

    test('moving strokes saves one undo step and undoes exactly', () async {
      final s = open();
      await s.load();
      s.addInk(samples: stroke('a').samples, width: 2, color: 0xFF000000);
      await s.settled();
      final before = s.ink.byId(s.ink.all.single.id)!;
      final moved = before.translated(30, 40);
      s.ink.add(moved);
      s.commitMove([moved]);
      await s.settled();
      expect((s.ink.all.single.bounds), moved.bounds);
      await s.undo();
      expect(s.ink.all.single.bounds, before.bounds);
    });

    test('recoloring strokes is one undo step', () async {
      final s = open();
      await s.load();
      s.addInk(samples: stroke('a').samples, width: 2, color: 0xFF2B2723);
      await s.settled();
      final id = s.ink.all.single.id;
      s.recolorMarks([MarkRef(MarkKind.ink, id)], inkColor: 0xFF0000FF);
      await s.settled();
      expect(s.ink.byId(id)!.color, 0xFF0000FF);
      await s.undo();
      expect(s.ink.byId(id)!.color, 0xFF2B2723);
    });

    test('deleting strokes removes them and undoes cleanly', () async {
      final s = open();
      await s.load();
      s.addInk(samples: stroke('a').samples, width: 2, color: 0xFF000000);
      await s.settled();
      final id = s.ink.all.single.id;
      s.deleteMarks([MarkRef(MarkKind.ink, id)]);
      await s.settled();
      expect(s.ink.count, 0);
      expect(await storedInk(), isEmpty);
      await s.undo();
      expect(s.ink.count, 1);
    });
  });

  group('cutting a stroke with the Select tool', () {
    test('the pieces replace the original in one undo step', () async {
      final s = open();
      await s.load();
      s.addInk(
        samples: Float32List.fromList([0, 0, 0.5, 100, 0, 0.5]),
        width: 2,
        color: 0xFF000000,
      );
      await s.settled();
      final first = s.ink.all.single.id;
      final a = s.newId(), b = s.newId();
      Ink piece(String id, double x0, double x1) => Ink(
        id: id,
        docId: docId,
        samples: Float32List.fromList([x0, 0, 0.5, x1, 0, 0.5]),
        width: 2,
        color: 0xFF000000,
      );
      s.ink.remove(first);
      s.ink.add(piece(a, 0, 40));
      s.ink.add(piece(b, 40, 100));
      s.commitCut(
        deleted: {first},
        created: [piece(a, 0, 40), piece(b, 40, 100)],
      );
      await s.settled();
      expect((await storedInk()).length, 2);
      expect(s.bus.undoLabel, 'Select');
      await s.undo();
      expect(s.ink.count, 1);
      expect(s.ink.all.single.id, first, reason: 'whole again');
      await s.redo();
      expect(s.ink.count, 2);
    });

    test('selecting alone never deletes anything', () async {
      final s = open();
      await s.load();
      s.addInk(
        samples: Float32List.fromList([0, 0, 0.5, 100, 0, 0.5]),
        width: 2,
        color: 0xFF000000,
      );
      await s.settled();
      expect(s.bus.undoDepth, 1);
      expect((await storedInk()).length, 1);
    });
  });

  group('remembered view', () {
    test('the view is saved after it settles and restored on open', () async {
      final s = open();
      await s.load();
      s.controller.setView(const ViewState(x: 120, y: 60, zoom: 1.5));
      await Future.delayed(const Duration(milliseconds: 120));
      expect(await db.viewState(docId), isNotNull);
      final again = open();
      await again.load();
      // The screen restores the saved view once the first layout is known.
      final saved = await again.savedView();
      again.controller.setView(saved!);
      expect(again.controller.view.value.zoom, 1.5);
    });
  });
}
