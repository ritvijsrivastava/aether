import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/hlc/hlc.dart';
import '../../domain/ops/entity_state.dart';
import '../../domain/ops/op.dart';
import '../../domain/ops/op_store.dart';
import 'database.dart';

/// [OpStore] backed by Drift/SQLite.
///
/// `commit` appends to the log and updates the snapshot inside one
/// transaction, so a crash can never leave them disagreeing.
class DriftOpStore implements OpStore {
  DriftOpStore(this._db);
  final AetherDatabase _db;

  @override
  Future<void> commit(List<Op> ops) {
    if (ops.isEmpty) return Future.value();
    return _db.transaction(() async {
      final cache = <String, EntityState>{};
      for (final op in ops) {
        await _db
            .into(_db.ops)
            .insert(
              OpsCompanion.insert(
                opId: op.opId,
                hlc: op.hlc.encode(),
                deviceId: op.hlc.deviceId,
                entityKind: op.entityKind.name,
                entityId: op.entityId,
                opKind: op.kind.name,
                field: Value(op.field),
                value: Value(op.value == null ? null : jsonEncode(op.value)),
                txGroupId: op.txGroupId,
                undoOf: Value(op.undoOf),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        final cur =
            cache[op.entityId] ??
            await entity(op.entityId) ??
            EntityState(id: op.entityId, kind: op.entityKind);
        cache[op.entityId] = cur.applyOp(op);
      }
      for (final s in cache.values) {
        await _upsert(s);
      }
    });
  }

  @override
  Future<EntityState?> entity(String id) async {
    final row = await (_db.select(
      _db.entities,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toState(row);
  }

  @override
  Future<List<EntityState>> entities({
    EntityKind? kind,
    String? docId,
    bool includeDeleted = false,
  }) async {
    final q = _db.select(_db.entities);
    q.where((e) {
      Expression<bool> w = const Constant(true);
      if (kind != null) w = w & e.kind.equals(kind.name);
      if (docId != null) w = w & e.docId.equals(docId);
      if (!includeDeleted) w = w & e.deleted.equals(false);
      return w;
    });
    return [for (final r in await q.get()) _toState(r)];
  }

  @override
  Future<List<Op>> allOps() async {
    final rows = await (_db.select(
      _db.ops,
    )..orderBy([(o) => OrderingTerm.asc(o.hlc)])).get();
    return [
      for (final r in rows)
        Op(
          opId: r.opId,
          hlc: Hlc.parse(r.hlc),
          entityKind: EntityKind.values.byName(r.entityKind),
          entityId: r.entityId,
          kind: OpKind.values.byName(r.opKind),
          txGroupId: r.txGroupId,
          field: r.field,
          value: r.value == null ? null : jsonDecode(r.value!),
          undoOf: r.undoOf,
        ),
    ];
  }

  /// Throws the snapshot away and rebuilds it from the log alone.
  /// Used by tests and as a recovery path.
  Future<void> rebuildSnapshots() async {
    final ops = await allOps();
    await _db.transaction(() async {
      await _db.delete(_db.entities).go();
      for (final s in materialize(ops).values) {
        await _upsert(s);
      }
    });
  }

  Future<void> _upsert(EntityState s) {
    final f = s.fields;
    double? d(String k) => (f[k] as num?)?.toDouble();
    final isDoc = s.kind == EntityKind.document;
    return _db
        .into(_db.entities)
        .insertOnConflictUpdate(
          EntitiesCompanion(
            id: Value(s.id),
            kind: Value(s.kind.name),
            docId: Value(isDoc ? s.id : f['docId'] as String?),
            pageId: Value(
              s.kind == EntityKind.page ? s.id : f['pageId'] as String?,
            ),
            markType: Value(f['type'] as String?),
            bx0: Value(d('bx0')),
            by0: Value(d('by0')),
            bx1: Value(d('bx1')),
            by1: Value(d('by1')),
            fields: Value(jsonEncode(f)),
            fieldHlcs: Value(
              jsonEncode({
                for (final e in s.fieldHlcs.entries) e.key: e.value.encode(),
              }),
            ),
            lifeHlc: Value(s.lifeHlc?.encode()),
            deleted: Value(s.deleted),
            createdHlc: Value(s.createdHlc?.encode()),
          ),
        );
  }

  EntityState _toState(EntityRow r) => EntityState(
    id: r.id,
    kind: EntityKind.values.byName(r.kind),
    fields: Map<String, Object?>.from(jsonDecode(r.fields) as Map),
    fieldHlcs: {
      for (final e in (jsonDecode(r.fieldHlcs) as Map).entries)
        e.key as String: Hlc.parse(e.value as String),
    },
    lifeHlc: r.lifeHlc == null ? null : Hlc.parse(r.lifeHlc!),
    deleted: r.deleted,
    createdHlc: r.createdHlc == null ? null : Hlc.parse(r.createdHlc!),
  );
}
