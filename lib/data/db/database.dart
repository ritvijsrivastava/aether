import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/id/id_generator.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Ops, Entities, PdfFiles, Device, Settings, ViewStates])
class AetherDatabase extends _$AetherDatabase {
  AetherDatabase(super.e);

  /// Bump together with a migration step below, and add a fixture test.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v1 is the baseline. Future versions add `if (from < N)` steps here.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// This install's device id, created on first call.
  Future<String> deviceId() async {
    final row = await (select(
      device,
    )..where((d) => d.slot.equals(0))).getSingleOrNull();
    if (row != null) return row.deviceId;
    final id = newDeviceId();
    // Explicit slot 0: a lone integer primary key is a rowid alias, so the
    // column default would be ignored and every call would add a new row.
    await into(device).insert(
      DeviceCompanion.insert(slot: const Value(0), deviceId: id),
      mode: InsertMode.insertOrIgnore,
    );
    return (await (select(
      device,
    )..where((d) => d.slot.equals(0))).getSingle()).deviceId;
  }

  // --- imported PDFs (local only, never synced) -----------------------------

  Future<PdfFileRow?> pdfFile(String sourceHash) => (select(
    pdfFiles,
  )..where((f) => f.sourceHash.equals(sourceHash))).getSingleOrNull();

  Future<void> putPdfFile({
    required String sourceHash,
    required String path,
    required int byteLength,
    required DateTime importedAt,
  }) => into(pdfFiles).insertOnConflictUpdate(
    PdfFilesCompanion.insert(
      sourceHash: sourceHash,
      path: path,
      byteLength: byteLength,
      importedAt: importedAt.millisecondsSinceEpoch,
    ),
  );

  // --- per-document view (local only) ---------------------------------------

  Future<ViewStateRow?> viewState(String docId) => (select(
    viewStates,
  )..where((v) => v.docId.equals(docId))).getSingleOrNull();

  Future<void> putViewState(String docId, double x, double y, double zoom) =>
      into(viewStates).insertOnConflictUpdate(
        ViewStatesCompanion.insert(docId: docId, x: x, y: y, zoom: zoom),
      );

  Future<String?> setting(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> putSetting(String key, String value) => into(settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}

/// Opens the on-disk database in a background isolate with WAL enabled.
Future<AetherDatabase> openAetherDatabase({String name = 'aether.db'}) async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, name));
  return AetherDatabase(openDatabaseFile(file));
}

/// A database connection at [file] (WAL, synchronous NORMAL).
QueryExecutor openDatabaseFile(File file) => NativeDatabase.createInBackground(
  file,
  setup: (db) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
  },
);
