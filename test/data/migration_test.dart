import 'package:aether/data/db/database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../generated_migrations/schema.dart';

/// Guards the schema: the live database must match the committed v1 dump
/// (`drift_schemas/`). When schemaVersion changes, run
///   dart run drift_dev schema dump lib/data/db/database.dart drift_schemas/
///   dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
/// then add a `from -> to` case here that seeds data at the old version.
void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('fresh install matches the v1 baseline schema', () async {
    final connection = await verifier.startAt(1);
    final db = AetherDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });
}
