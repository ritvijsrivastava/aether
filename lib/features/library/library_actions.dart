import '../../core/id/id_generator.dart';
import '../../domain/commands/command.dart';
import '../../domain/commands/command_bus.dart';
import '../../domain/model/models.dart';
import '../../domain/ops/op.dart';
import '../../domain/ops/op_store.dart';

/// Rename and delete for the library, each undoable; and board creation.
class LibraryActions {
  LibraryActions({required this.store, required this.bus, required this.ids})
    : _factory = CommandFactory(store);

  final OpStore store;
  final CommandBus bus;
  final IdGenerator ids;
  final CommandFactory _factory;

  /// A new empty board. Returns its id.
  Future<String> createBoard() async {
    final id = ids.next();
    await bus.run(
      _factory.create(EntityKind.document, id, {
        'title': 'Untitled board',
      }, label: 'New board'),
    );
    return id;
  }

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
