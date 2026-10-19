import 'entity_state.dart';
import 'op.dart';

/// Persistence boundary for the operation log and its materialized snapshot.
abstract interface class OpStore {
  /// Appends [ops] to the log and updates the snapshot in one atomic step.
  Future<void> commit(List<Op> ops);

  Future<EntityState?> entity(String id);

  /// Entities matching the filters. Deleted ones are skipped by default.
  Future<List<EntityState>> entities({
    EntityKind? kind,
    String? docId,
    bool includeDeleted = false,
  });

  /// The full log in HLC order.
  Future<List<Op>> allOps();
}
