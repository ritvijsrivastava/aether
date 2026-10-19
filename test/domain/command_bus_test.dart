import 'dart:math';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/domain/commands/command.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_op_store.dart';

({CommandBus bus, CommandFactory cmd, MemoryOpStore store}) rig() {
  final store = MemoryOpStore();
  var t = 1000;
  final bus = CommandBus(
    store: store,
    clock: HlcClock('dev1', now: () => t++),
    ids: SequentialIdGenerator('x'),
  );
  return (bus: bus, cmd: CommandFactory(store), store: store);
}

Map<String, Map<String, Object?>> snap(MemoryOpStore s) => {
  for (final e in s.view().entries) e.key: {...e.value},
};

void main() {
  test('undo of a create hides the entity; redo brings it back', () async {
    final r = rig();
    await r.bus.run(
      r.cmd.create(EntityKind.mark, 'm1', {'type': 'note', 'text': 'hi'}),
    );
    expect(r.store.view().keys, ['m1']);
    await r.bus.undo();
    expect(r.store.view(), isEmpty);
    await r.bus.redo();
    expect(r.store.view()['m1'], {'type': 'note', 'text': 'hi'});
  });

  test('undo restores the exact previous field values', () async {
    final r = rig();
    await r.bus.run(r.cmd.create(EntityKind.mark, 'm1', {'text': 'a', 'x': 1}));
    await r.bus.run(await r.cmd.setFields('m1', {'text': 'b', 'x': 2}));
    await r.bus.undo();
    expect(r.store.view()['m1'], {'text': 'a', 'x': 1});
  });

  test('a new action clears the redo stack', () async {
    final r = rig();
    await r.bus.run(r.cmd.create(EntityKind.mark, 'a', {}));
    await r.bus.undo();
    expect(r.bus.canRedo, isTrue);
    await r.bus.run(r.cmd.create(EntityKind.mark, 'b', {}));
    expect(r.bus.canRedo, isFalse);
  });

  test('undo and redo append to the log, never rewrite it', () async {
    final r = rig();
    await r.bus.run(r.cmd.create(EntityKind.mark, 'm1', {'x': 1}));
    final before = (await r.store.allOps()).length;
    await r.bus.undo();
    final ops = await r.store.allOps();
    expect(ops.length, greaterThan(before));
    expect(ops.where((o) => o.undoOf != null), isNotEmpty);
    expect(ops.map((o) => o.opId).toSet().length, ops.length);
  });

  test('a grouped command undoes as one step', () async {
    final r = rig();
    await r.bus.run(r.cmd.create(EntityKind.mark, 'a', {'x': 1}));
    await r.bus.run(r.cmd.create(EntityKind.mark, 'b', {'x': 2}));
    final del = Command.group('Delete 2', [
      await r.cmd.delete('a'),
      await r.cmd.delete('b'),
    ]);
    await r.bus.run(del);
    expect(r.store.view(), isEmpty);
    await r.bus.undo();
    expect(r.store.view().keys.toSet(), {'a', 'b'});
  });

  test('random action sequences: undo walks back through every state, redo forward', () async {
    for (var seed = 0; seed < 20; seed++) {
      final rnd = Random(seed);
      final r = rig();
      final states = <Map<String, Map<String, Object?>>>[snap(r.store)];
      final ids = <String>[];
      for (var i = 0; i < 25; i++) {
        final pick = rnd.nextInt(4);
        if (ids.isEmpty || pick == 0) {
          final id = 'm${ids.length}';
          ids.add(id);
          await r.bus.run(
            r.cmd.create(EntityKind.mark, id, {
              'x': rnd.nextInt(50),
              'text': 't$i',
            }),
          );
        } else if (pick == 3) {
          await r.bus.run(await r.cmd.delete(ids[rnd.nextInt(ids.length)]));
        } else {
          await r.bus.run(
            await r.cmd.setFields(ids[rnd.nextInt(ids.length)], {
              'x': rnd.nextInt(50),
              if (rnd.nextBool()) 'text': 'e$i',
            }),
          );
        }
        // A no-op command (e.g. delete of an already-deleted entity) pushes nothing.
        if (states.length - 1 < _depth(r.bus)) states.add(snap(r.store));
      }
      for (var k = states.length - 2; k >= 0; k--) {
        await r.bus.undo();
        expect(snap(r.store), states[k], reason: 'seed $seed undo to step $k');
      }
      expect(r.bus.canUndo, isFalse);
      for (var k = 1; k < states.length; k++) {
        await r.bus.redo();
        expect(snap(r.store), states[k], reason: 'seed $seed redo to step $k');
      }
    }
  });

  test('undo depth is capped', () async {
    final store = MemoryOpStore();
    var t = 0;
    final bus = CommandBus(
      store: store,
      clock: HlcClock('d', now: () => t++),
      ids: SequentialIdGenerator(),
      maxUndo: 3,
    );
    final f = CommandFactory(store);
    for (var i = 0; i < 10; i++) {
      await bus.run(f.create(EntityKind.mark, 'm$i', {}));
    }
    var n = 0;
    while (await bus.undo()) {
      n++;
    }
    expect(n, 3);
  });
}

int _depth(CommandBus b) => b.undoDepth;
