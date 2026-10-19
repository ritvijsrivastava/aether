// THROWAWAY (M0 spike): proves Drift + SQLite builds and runs on both targets.
import 'package:drift/drift.dart';

part 'spike_db.g.dart';

class Marks extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  BlobColumn get payload => blob()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Marks])
class SpikeDb extends _$SpikeDb {
  SpikeDb(super.e);

  @override
  int get schemaVersion => 1;
}
