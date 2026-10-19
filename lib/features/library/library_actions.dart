import '../../domain/commands/command.dart';
import '../../domain/commands/command_bus.dart';
import '../../domain/model/models.dart';
import '../../domain/ops/op_store.dart';

/// Rename and delete for the library, each undoable.
class LibraryActions {
  LibraryActions({required this.store, required this.bus})
    : _factory = CommandFactory(store);

  final OpStore store;
  final CommandBus bus;
  final CommandFactory _factory;

  Future<void> rename(String docId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    await bus.run(
      await _factory.setFields(docId, {F.title: clean}, label: 'Rename'),
    );
  }

  /// Deletes the document (a tombstone: its pages, marks and PDF stay on disk
  /// until a later purge, so [undo] restores everything).
  Future<void> delete(String docId) async {
    final Command c = await _factory.delete(docId, label: 'Delete');
    await bus.run(c);
  }

  Future<bool> undo() => bus.undo();
}
