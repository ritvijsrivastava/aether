import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../../core/hlc/hlc.dart';
import 'op.dart';

const _deep = DeepCollectionEquality();

/// The materialized state of one entity: a last-writer-wins map of fields
/// plus a last-writer-wins life flag (created/restored vs deleted).
///
/// [applyOp] is commutative and idempotent, so any order of the same ops
/// yields the same state. That is what makes sync possible later.
@immutable
class EntityState {
  const EntityState({
    required this.id,
    required this.kind,
    this.fields = const {},
    this.fieldHlcs = const {},
    this.lifeHlc,
    this.deleted = false,
    this.createdHlc,
  });

  final String id;
  final EntityKind kind;
  final Map<String, Object?> fields;
  final Map<String, Hlc> fieldHlcs;

  /// Timestamp of the latest create/delete/restore that won.
  final Hlc? lifeHlc;
  final bool deleted;

  /// Earliest create op seen.
  final Hlc? createdHlc;

  /// Hlc of the most recent change of any kind.
  Hlc? get updatedHlc {
    Hlc? best = lifeHlc;
    for (final h in fieldHlcs.values) {
      if (best == null || h > best) best = h;
    }
    return best;
  }

  T? field<T>(String name) => fields[name] as T?;

  EntityState applyOp(Op op) {
    switch (op.kind) {
      case OpKind.create:
      case OpKind.restore:
      case OpKind.delete:
        final wins = lifeHlc == null || op.hlc > lifeHlc!;
        final created =
            op.kind == OpKind.create &&
                (createdHlc == null || op.hlc < createdHlc!)
            ? op.hlc
            : createdHlc;
        return EntityState(
          id: id,
          kind: kind,
          fields: fields,
          fieldHlcs: fieldHlcs,
          lifeHlc: wins ? op.hlc : lifeHlc,
          deleted: wins ? op.kind == OpKind.delete : deleted,
          createdHlc: created,
        );
      case OpKind.setField:
        final f = op.field!;
        final cur = fieldHlcs[f];
        if (cur != null && op.hlc <= cur) return this;
        return EntityState(
          id: id,
          kind: kind,
          fields: {...fields, f: op.value},
          fieldHlcs: {...fieldHlcs, f: op.hlc},
          lifeHlc: lifeHlc,
          deleted: deleted,
          createdHlc: createdHlc,
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is EntityState &&
      other.id == id &&
      other.kind == kind &&
      other.deleted == deleted &&
      other.lifeHlc == lifeHlc &&
      other.createdHlc == createdHlc &&
      _deep.equals(other.fields, fields) &&
      _deep.equals(other.fieldHlcs, fieldHlcs);

  @override
  int get hashCode => Object.hash(id, kind, deleted, lifeHlc, createdHlc);

  @override
  String toString() => 'EntityState($kind $id deleted=$deleted fields=$fields)';
}

/// Folds [ops] (in any order) into entity states.
Map<String, EntityState> materialize(Iterable<Op> ops) {
  final out = <String, EntityState>{};
  for (final op in ops) {
    final s =
        out[op.entityId] ?? EntityState(id: op.entityId, kind: op.entityKind);
    out[op.entityId] = s.applyOp(op);
  }
  return out;
}
