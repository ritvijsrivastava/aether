import 'package:drift/drift.dart';

/// Append-only operation log. One row per [Op]; never updated or deleted.
@DataClassName('OpRow')
@TableIndex(name: 'ops_hlc', columns: {#hlc})
@TableIndex(name: 'ops_entity', columns: {#entityId})
class Ops extends Table {
  TextColumn get opId => text()();
  TextColumn get hlc => text()();
  TextColumn get deviceId => text()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  TextColumn get opKind => text()();
  TextColumn get field => text().nullable()();

  /// JSON-encoded value (null for non-setField ops).
  TextColumn get value => text().nullable()();
  TextColumn get txGroupId => text()();
  TextColumn get undoOf => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};
}

/// Materialized snapshot of every entity, rebuildable from [Ops] alone.
///
/// Documents, pages, marks, links and categories share one table because they
/// share one merge rule (last-writer-wins per field). The indexed columns are
/// copies of well-known fields so region and per-document queries stay fast.
@DataClassName('EntityRow')
@TableIndex(name: 'entities_doc_kind', columns: {#docId, #kind})
@TableIndex(name: 'entities_page', columns: {#pageId})
class Entities extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get docId => text().nullable()();
  TextColumn get pageId => text().nullable()();
  TextColumn get markType => text().nullable()();
  RealColumn get bx0 => real().nullable()();
  RealColumn get by0 => real().nullable()();
  RealColumn get bx1 => real().nullable()();
  RealColumn get by1 => real().nullable()();

  /// JSON map: field name to value.
  TextColumn get fields => text()();

  /// JSON map: field name to encoded HLC.
  TextColumn get fieldHlcs => text()();
  TextColumn get lifeHlc => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get createdHlc => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Imported PDFs, content-addressed. Local only; never synced.
@DataClassName('PdfFileRow')
class PdfFiles extends Table {
  TextColumn get sourceHash => text()();
  TextColumn get path => text()();
  IntColumn get byteLength => integer()();
  IntColumn get importedAt => integer()();

  @override
  Set<Column> get primaryKey => {sourceHash};
}

/// Single-row table holding this install's device id.
@DataClassName('DeviceRow')
class Device extends Table {
  IntColumn get slot => integer().withDefault(const Constant(0))();
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {slot};
}

/// Local preferences (theme, finger-draws, ...). Never synced.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Per-document viewport (pan, zoom). Local only; never synced.
@DataClassName('ViewStateRow')
class ViewStates extends Table {
  TextColumn get docId => text()();
  RealColumn get x => real()();
  RealColumn get y => real()();
  RealColumn get zoom => real()();

  @override
  Set<Column> get primaryKey => {docId};
}
