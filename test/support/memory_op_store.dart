import 'package:aether/domain/ops/entity_state.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:aether/domain/ops/op_store.dart';

/// Reference [OpStore] used to test domain logic without a database.
class MemoryOpStore implements OpStore {
  final List<Op> _log = [];
  final Map<String, EntityState> _state = {};
  final Set<String> _seen = {};

  @override
  Future<void> commit(List<Op> ops) async {
    for (final op in ops) {
      if (!_seen.add(op.opId)) continue;
      _log.add(op);
      final cur =
          _state[op.entityId] ??
          EntityState(id: op.entityId, kind: op.entityKind);
      _state[op.entityId] = cur.applyOp(op);
    }
  }

  @override
  Future<EntityState?> entity(String id) async => _state[id];

  @override
  Future<List<EntityState>> entities({
    EntityKind? kind,
    String? docId,
    bool includeDeleted = false,
  }) async => [
    for (final s in _state.values)
      if ((kind == null || s.kind == kind) &&
          (docId == null || s.fields['docId'] == docId || s.id == docId) &&
          (includeDeleted || !s.deleted))
        s,
  ];

  @override
  Future<List<Op>> allOps() async =>
      [..._log]..sort((a, b) => a.hlc.compareTo(b.hlc));

  /// Visible (non-deleted) entities with non-null fields, for comparisons.
  Map<String, Map<String, Object?>> view() => {
    for (final s in _state.values)
      if (!s.deleted)
        s.id: {
          for (final e in s.fields.entries)
            if (e.value != null) e.key: e.value,
        },
  };
}
