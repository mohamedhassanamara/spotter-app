import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v1.dart' as v1;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 → v2 creates the media tables and keeps existing data', () async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old.customStatement(
      "INSERT INTO sessions (name, started_at, status) VALUES ('Push A', 1760000000, 'finished')",
    );
    await old.customStatement("INSERT INTO app_settings (key, value) VALUES ('weekly_goal', '5')");
    await old.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);
    expect((await db.select(db.sessions).get()).single.name, 'Push A');
    expect(await db.getSetting('weekly_goal'), '5');
    expect(await db.select(db.mediaMatches).get(), isEmpty);
    expect(await db.select(db.pinnedVideos).get(), isEmpty);
    await db.close();
  });
}
