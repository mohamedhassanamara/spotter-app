import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/diagnostics/error_log.dart';
import 'package:spotter/bootstrap.dart';

import '../test/generated_migrations/schema_v2.dart' as v2;
import 'harness.dart';

/// Recreates what an existing install looks like before this build: a schema-v2 database with the
/// demo routines, a finished session and a workout still in progress from the old build.
Future<void> _writeV2Install() async {
  final docs = await getApplicationDocumentsDirectory();
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('${docs.path}/spotter.sqlite$suffix');
    if (f.existsSync()) f.deleteSync();
  }
  final old = v2.DatabaseAtV2(NativeDatabase(File('${docs.path}/spotter.sqlite')));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  int ago(Duration d) => now - d.inSeconds;
  Future<void> sql(String s, [List<Object?> args = const []]) => old.customStatement(s, args);

  await sql('INSERT INTO exercises (id, name, primary_muscles, secondary_muscles, equipment, mechanic, instructions, images) '
      "VALUES ('Barbell_Bench_Press_-_Medium_Grip', 'Barbell Bench Press - Medium Grip', '[\"chest\"]', '[\"triceps\"]', 'barbell', 'compound', '[]', '[]')");
  for (final (k, v) in [('onboarded', 'true'), ('exercise_dataset_version', '1'), ('weekly_goal', '6'), ('rank_ladder_version', '2')]) {
    await sql('INSERT INTO app_settings (key, value) VALUES (?, ?)', [k, v]);
  }
  await sql('INSERT INTO body_weights (measured_at, kg, source) VALUES (?, 80, ?)', [ago(const Duration(days: 3)), 'manual']);
  await sql("INSERT INTO routines (id, name, position, created_at) VALUES (1, 'Push A', 0, ?)", [ago(const Duration(days: 30))]);
  await sql('INSERT INTO routine_exercises (routine_id, exercise_id, position, rep_min, rep_max, target_sets, rest_seconds, target_rir) '
      "VALUES (1, 'Barbell_Bench_Press_-_Medium_Grip', 0, 6, 10, 3, 150, 2)");

  const sug = '{"headline":"Today: 60 kg × 8, 3 sets, stop at 2 reps in reserve","why":["Old build"],"technique":false,"ramp":false,"band":"green"}';
  // A finished session two days ago.
  await sql("INSERT INTO sessions (id, routine_id, name, started_at, ended_at, status) VALUES (1, 1, 'Push A', ?, ?, 'finished')",
      [ago(const Duration(days: 2, hours: 1)), ago(const Duration(days: 2))]);
  await sql('INSERT INTO session_exercises (id, session_id, exercise_id, position, rep_min, rep_max, target_sets, rest_seconds, target_rir, suggestion_kind, suggested_weight, suggested_reps, suggested_sets, suggestion_json) '
      "VALUES (1, 1, 'Barbell_Bench_Press_-_Medium_Grip', 0, 6, 10, 3, 150, 2, 'addReps', 60, 8, 3, ?)", [sug]);
  for (var i = 0; i < 3; i++) {
    await sql('INSERT INTO workout_sets (session_exercise_id, position, weight, reps, rpe, completed, completed_at, suggested_weight, suggested_reps) VALUES (1, ?, 60, 8, 8, 1, ?, 60, 8)',
        [i, ago(const Duration(days: 2, minutes: 30))]);
  }
  // The workout in progress when the app was updated: 1 of 3 sets done.
  await sql("INSERT INTO sessions (id, routine_id, name, started_at, status) VALUES (2, 1, 'Push A', ?, 'active')", [ago(const Duration(minutes: 20))]);
  await sql('INSERT INTO session_exercises (id, session_id, exercise_id, position, rep_min, rep_max, target_sets, rest_seconds, target_rir, suggestion_kind, suggested_weight, suggested_reps, suggested_sets, suggestion_json) '
      "VALUES (2, 2, 'Barbell_Bench_Press_-_Medium_Grip', 0, 6, 10, 3, 150, 2, 'addReps', 60, 9, 3, ?)", [sug]);
  await sql('INSERT INTO workout_sets (session_exercise_id, position, weight, reps, rpe, completed, completed_at, suggested_weight, suggested_reps) VALUES (2, 0, 60, 9, 8, 1, ?, 60, 9)',
      [ago(const Duration(minutes: 10))]);
  for (var i = 1; i < 3; i++) {
    await sql('INSERT INTO workout_sets (session_exercise_id, position, weight, reps, completed, suggested_weight, suggested_reps) VALUES (2, ?, 60, 9, 0, 60, 9)', [i]);
  }
  await old.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('upgrade from schema v2 with demo routines and a workout in progress', (tester) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await tester.runAsync(_writeV2Install);
    await ErrorLog.instance.init();
    await ErrorLog.instance.clear();

    final h = AppHarness(tester);
    h.db = AppDatabase.open(); // migrates v2 → v3
    await tester.runAsync(() => bootstrapDatabase(h.db!)); // exactly what main() does
    await h.pumpApp();

    // My routines replaced the demo ones before the first frame; the old workout is still resumable.
    final routines = await tester.runAsync(() => h.db!.select(h.db!.routines).get());
    await h.expectNoLoggedErrors();
    expect(routines!.map((r) => r.name).toSet(), {'Upper', 'Lower', 'Push', 'Pull', 'Arms'});

    await h.tap(find.text('Resume Push A'));
    await h.waitFor(find.text('Barbell Bench Press - Medium Grip'), reason: 'old in-progress exercise');
    // Finish the two remaining sets from the old build, then the workout.
    for (var i = 0; i < 2; i++) {
      await h.tap(find.byTooltip('Complete set'));
      if (find.text('Skip').evaluate().isNotEmpty) await h.tap(find.text('Skip'));
    }
    await h.tap(find.text('Finish'));
    await h.waitFor(find.text('WORKOUT COMPLETE'), timeout: const Duration(seconds: 30), reason: 'summary after upgrade');
    await h.tap(find.text('Done'));

    // Train now shows my five routines and can start one.
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Upper'));
    expect(find.text('Push A'), findsNothing);
    await h.tap(find.text('Start'));
    await h.waitFor(find.text('Chest Press'), reason: 'program routine starts after upgrade');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
