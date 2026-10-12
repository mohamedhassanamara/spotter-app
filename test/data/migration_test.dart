import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v1.dart' as v1;
import '../generated_migrations/schema_v2.dart' as v2;
import '../generated_migrations/schema_v3.dart' as v3;
import '../generated_migrations/schema_v4.dart' as v4;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 → current creates the media tables and keeps existing data', () async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old.customStatement(
      "INSERT INTO sessions (name, started_at, status) VALUES ('Push A', 1760000000, 'finished')",
    );
    await old.customStatement("INSERT INTO app_settings (key, value) VALUES ('weekly_goal', '5')");
    await old.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 6);
    expect((await db.select(db.sessions).get()).single.name, 'Push A');
    expect(await db.getSetting('weekly_goal'), '5');
    expect(await db.select(db.mediaMatches).get(), isEmpty);
    expect(await db.select(db.pinnedVideos).get(), isEmpty);
    await db.close();
  });
  test('v2 → v3 adds program/prescription columns, keeps data', () async {
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    await old.customStatement("INSERT INTO routines (name, position, created_at) VALUES ('Push A', 0, 1760000000)");
    await old.close();
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 6);
    final r = (await db.select(db.routines).get()).single;
    expect(r.name, 'Push A');
    expect(r.programDay, isNull);
    await db.close();
  });

  test('v3 → v4 marks existing sessions as app sessions and allows one import per external id', () async {
    final schema = await verifier.schemaAt(3);
    final old = v3.DatabaseAtV3(schema.newConnection());
    await old.customStatement("INSERT INTO sessions (name, started_at, status) VALUES ('Upper', 1760000000, 'finished')");
    await old.close();
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 6);
    final s = (await db.select(db.sessions).get()).single;
    expect(s.source, 'app');
    expect(s.externalId, isNull);
    Future<void> insert() => db.customStatement(
        "INSERT INTO sessions (name, started_at, status, source, external_id) VALUES ('L', 1, 'finished', 'liftoff', '2026-06-12 08:44:09')");
    await insert();
    await expectLater(insert(), throwsA(anything));
    await db.close();
  });

  test('v4 → v5 adds set types, per-exercise rest toggle and superset groups, keeps data', () async {
    final schema = await verifier.schemaAt(4);
    final old = v4.DatabaseAtV4(schema.newConnection());
    await old.customStatement("INSERT INTO sessions (id, name, started_at, status) VALUES (1, 'Push', 1760000000, 'active')");
    await old.customStatement("INSERT INTO exercises (id, name) VALUES ('X', 'X')");
    await old.customStatement(
        "INSERT INTO session_exercises (id, session_id, exercise_id, position, rep_min, rep_max, target_sets, rest_seconds) VALUES (1, 1, 'X', 0, 6, 8, 2, 120)");
    await old.customStatement('INSERT INTO workout_sets (session_exercise_id, position, weight, reps) VALUES (1, 0, 60, 8)');
    await old.close();
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 6);
    final e = (await db.select(db.sessionExercises).get()).single;
    expect(e.restEnabled, isTrue);
    expect(e.supersetGroup, isNull);
    expect((await db.select(db.workoutSets).get()).single.setType, isNull);
    await db.close();
  });

  test('v5 → v6 adds the ExerciseDB V2 mapping table', () async {
    final schema = await verifier.schemaAt(5);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 6);
    expect(await db.select(db.edbV2Maps).get(), isEmpty);
    await db.close();
  });

  test('v1 → v6 in one go', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 6);
    await db.close();
  });
}
