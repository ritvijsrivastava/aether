import 'package:meta/meta.dart';

import '../ops/op.dart';
import '../ops/op_store.dart';

/// A user action expressed as the ops that perform it and the ops that undo it.
@immutable
class Command {
  const Command(this.label, this.forward, this.inverse);

  final String label;
  final List<OpDraft> forward;
  final List<OpDraft> inverse;

  bool get isEmpty => forward.isEmpty;

  /// Concatenates commands into one atomic action (inverse runs in reverse).
  factory Command.group(String label, List<Command> parts) => Command(
    label,
    [for (final c in parts) ...c.forward],
    [for (final c in parts.reversed) ...c.inverse],
  );
}

/// Builds [Command]s by reading current state, so each one carries its own
/// inverse (the values it replaced).
class CommandFactory {
  const CommandFactory(this._store);
  final OpStore _store;

  /// Creates an entity with initial [fields].
  Command create(
    EntityKind kind,
    String id,
    Map<String, Object?> fields, {
    String label = 'Add',
  }) => Command(
    label,
    [
      OpDraft.create(kind, id),
      for (final e in fields.entries) OpDraft.set(kind, id, e.key, e.value),
    ],
    [OpDraft.delete(kind, id)],
  );

  /// Sets [changes] on an existing entity; the inverse restores old values.
  Future<Command> setFields(
    String id,
    Map<String, Object?> changes, {
    String label = 'Edit',
  }) async {
    final cur = await _store.entity(id);
    if (cur == null) throw StateError('No such entity: $id');
    final fwd = <OpDraft>[];
    final inv = <OpDraft>[];
    for (final e in changes.entries) {
      if (cur.fields.containsKey(e.key) && cur.fields[e.key] == e.value) {
        continue;
      }
      fwd.add(OpDraft.set(cur.kind, id, e.key, e.value));
      inv.add(OpDraft.set(cur.kind, id, e.key, cur.fields[e.key]));
    }
    return Command(label, fwd, inv);
  }

  Future<Command> delete(String id, {String label = 'Delete'}) async {
    final cur = await _store.entity(id);
    if (cur == null || cur.deleted) return Command(label, const [], const []);
    return Command(
      label,
      [OpDraft.delete(cur.kind, id)],
      [OpDraft.restore(cur.kind, id)],
    );
  }
}
