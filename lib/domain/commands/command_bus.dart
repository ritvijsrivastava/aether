import 'dart:async';

import '../../core/hlc/hlc.dart';
import '../../core/id/id_generator.dart';
import '../ops/op.dart';
import '../ops/op_store.dart';
import 'command.dart';

class _Entry {
  _Entry(this.command, this.tx);
  final Command command;

  /// Transaction group of the most recent forward commit of [command].
  String tx;
}

/// Runs commands against the [OpStore] and keeps the undo/redo stacks.
///
/// Undo and redo never rewrite history: they append new ops (the inverse, or
/// the forward ops again) with fresh timestamps, so the log stays append-only.
class CommandBus {
  CommandBus({
    required this.store,
    required this.clock,
    required this.ids,
    this.maxUndo = 200,
  });

  final OpStore store;
  final HlcClock clock;
  final IdGenerator ids;
  final int maxUndo;

  final List<_Entry> _undo = [];
  final List<_Entry> _redo = [];

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires after every change to the stacks; use it to refresh Undo/Redo UI.
  Stream<void> get changes => _changes.stream;

  bool get canUndo => _undo.isNotEmpty;

  /// Number of undoable steps currently held.
  int get undoDepth => _undo.length;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.command.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.command.label;

  Future<void> run(Command c) async {
    if (c.isEmpty) return;
    final tx = ids.next();
    await _commit(c.forward, tx: tx);
    _undo.add(_Entry(c, tx));
    if (_undo.length > maxUndo) _undo.removeAt(0);
    _redo.clear();
    _changes.add(null);
  }

  Future<bool> undo() async {
    if (_undo.isEmpty) return false;
    final e = _undo.removeLast();
    await _commit(e.command.inverse, tx: ids.next(), undoOf: e.tx);
    _redo.add(e);
    _changes.add(null);
    return true;
  }

  Future<bool> redo() async {
    if (_redo.isEmpty) return false;
    final e = _redo.removeLast();
    e.tx = ids.next();
    await _commit(e.command.forward, tx: e.tx);
    _undo.add(e);
    _changes.add(null);
    return true;
  }

  Future<void> _commit(
    List<OpDraft> drafts, {
    required String tx,
    String? undoOf,
  }) {
    final ops = [
      for (final d in drafts)
        Op(
          opId: ids.next(),
          hlc: clock.send(),
          entityKind: d.entityKind,
          entityId: d.entityId,
          kind: d.kind,
          txGroupId: tx,
          field: d.field,
          value: d.value,
          undoOf: undoOf,
        ),
    ];
    return store.commit(ops);
  }

  void dispose() => _changes.close();
}
