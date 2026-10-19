import 'dart:math';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/domain/ops/entity_state.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:flutter_test/flutter_test.dart';

Op op(
  int n,
  String dev,
  OpKind k,
  String id, {
  String? field,
  Object? value,
  EntityKind ek = EntityKind.mark,
}) => Op(
  opId: 'op-$n-$dev',
  hlc: Hlc(n, 0, dev),
  entityKind: ek,
  entityId: id,
  kind: k,
  txGroupId: 'tx',
  field: field,
  value: value,
);

void main() {
  test('last writer wins per field', () {
    final s = materialize([
      op(1, 'a', OpKind.create, 'e'),
      op(2, 'a', OpKind.setField, 'e', field: 'x', value: 1),
      op(4, 'b', OpKind.setField, 'e', field: 'x', value: 3),
      op(3, 'a', OpKind.setField, 'e', field: 'x', value: 2),
    ])['e']!;
    expect(s.fields['x'], 3);
  });

  test('delete then later restore leaves the entity alive', () {
    final s = materialize([
      op(1, 'a', OpKind.create, 'e'),
      op(2, 'a', OpKind.delete, 'e'),
      op(3, 'a', OpKind.restore, 'e'),
    ])['e']!;
    expect(s.deleted, isFalse);
  });

  test('an edit does not resurrect a deleted entity', () {
    final s = materialize([
      op(1, 'a', OpKind.create, 'e'),
      op(2, 'a', OpKind.delete, 'e'),
      op(3, 'b', OpKind.setField, 'e', field: 'x', value: 1),
    ])['e']!;
    expect(s.deleted, isTrue);
    expect(s.fields['x'], 1, reason: 'field kept; restore would show it');
  });

  test('ops arriving before their create still materialize', () {
    final s = materialize([
      op(5, 'a', OpKind.setField, 'e', field: 'x', value: 9),
      op(1, 'a', OpKind.create, 'e'),
    ])['e']!;
    expect(s.fields['x'], 9);
    expect(s.deleted, isFalse);
    expect(s.createdHlc, const Hlc(1, 0, 'a'));
  });

  test('applying the same op twice changes nothing (idempotent)', () {
    final o = op(1, 'a', OpKind.setField, 'e', field: 'x', value: 1);
    final once = materialize([o])['e']!;
    final twice = materialize([o, o])['e']!;
    expect(twice, once);
  });

  test(
    'any permutation of the same ops gives the same state (commutative)',
    () {
      final rnd = Random(42);
      final ops = <Op>[];
      var n = 0;
      for (final dev in ['a', 'b', 'c']) {
        for (var i = 0; i < 40; i++) {
          final id = 'e${rnd.nextInt(5)}';
          final k = [
            OpKind.create,
            OpKind.setField,
            OpKind.setField,
            OpKind.delete,
            OpKind.restore,
          ][rnd.nextInt(5)];
          ops.add(
            op(
              ++n,
              dev,
              k,
              id,
              field: k == OpKind.setField ? 'f${rnd.nextInt(3)}' : null,
              value: k == OpKind.setField ? rnd.nextInt(100) : null,
            ),
          );
        }
      }
      final reference = materialize(ops);
      for (var trial = 0; trial < 25; trial++) {
        final shuffled = [...ops]..shuffle(rnd);
        expect(materialize(shuffled), reference);
      }
    },
  );
}
