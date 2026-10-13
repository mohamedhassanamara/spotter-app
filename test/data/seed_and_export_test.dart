import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/debug/data/seed_generator.dart';
import 'package:spotter/features/export/data/export_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('seed 12 weeks through the real pipeline, then export it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final exercises = ExerciseRepository(db);
    await exercises.ensureSeeded(jsonOverride: File('assets/exercises.json').readAsStringSync());
    final catalog = await exercises.watchCatalog().first;

    final now = DateTime(2026, 10, 12, 9);
    final report = await SeedGenerator(db).seed(now: now, catalog: catalog, settings: const SettingsModel());

    final finished = await (db.select(db.sessions)..where((t) => t.status.equals('finished'))).get();
    expect(finished.length, report.sessions);
    // Min-Max 5x layout: 5 sessions a week for 12 weeks, minus smart-rest skips.
    expect(report.sessions, greaterThan(45));
    expect(report.sessions, lessThanOrEqualTo(60));
    expect(report.freezes, greaterThanOrEqualTo(2));

    // Gradual progression: the working weight on the main (lowest-rep) slot trends up. Override
    // sets are excluded. (The simulated lifter stops at the top of the range +2 and logs an honest
    // low RPE when the load is light, so e1RM estimates from its sets are too noisy to compare.)
    for (final id in ['Leverage_Chest_Press', 'sp_pendulum_squat']) {
      final rows = await db.customSelect(
        'SELECT se.id AS ex, ws.weight AS w, ws.is_override AS o, ws.target_rep_max AS hi '
        'FROM session_exercises se JOIN sessions s ON s.id = se.session_id '
        'JOIN workout_sets ws ON ws.session_exercise_id = se.id '
        "WHERE se.exercise_id = ? AND ws.is_warmup = 0 AND se.suggestion_kind NOT IN ('calibration', 'egoFreeze') ORDER BY s.started_at",
        variables: [Variable.withString(id)],
      ).get();
      final mainHi = rows.map((r) => r.readNullable<int>('hi') ?? 99).reduce(math.min);
      final top = <int, double>{};
      for (final r in rows) {
        if (r.read<bool>('o') || (r.readNullable<int>('hi') ?? 99) != mainHi) continue;
        top[r.read<int>('ex')] = math.max(top[r.read<int>('ex')] ?? 0, r.read<double>('w'));
      }
      final series = top.values.toList();
      double avg(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;
      if (id == 'Leverage_Chest_Press') {
        expect(avg(series.skip(series.length - 3)), greaterThan(avg(series.take(3))), reason: '$id working weight should trend up');
      } else {
        // The simulated lifter stops exactly at the prescribed 2 in reserve on Pendulum's second set,
        // so it may hold; what must never happen is a spiral down (Fix 6).
        expect(avg(series.skip(series.length - 3)), greaterThanOrEqualTo(avg(series.take(3)) - 5), reason: '$id must not spiral down');
        final drops = [for (var i = 1; i < series.length; i++) series[i] < series[i - 1]];
        for (var i = 2; i < drops.length; i++) {
          expect(drops[i] && drops[i - 1] && drops[i - 2], isFalse, reason: '$id: never three decreases in a row');
        }
      }
    }
    final overrides = await (db.select(db.workoutSets)..where((t) => t.isOverride.equals(true))).get();
    expect(overrides, isNotEmpty);
    expect(overrides.every((s) => s.rpe != null && s.overrideReason != null), isTrue);
    expect(await db.select(db.achievementsUnlocked).get(), isNotEmpty);

    final dir = await Directory.systemTemp.createTemp('spotter_export');
    addTearDown(() => dir.delete(recursive: true));
    final export = ExportService(db);

    final json = jsonDecode(await (await export.writeJson(dir, now)).readAsString()) as Map<String, dynamic>;
    expect(json['schema_version'], 1);
    final sessions = json['sessions'] as List<dynamic>;
    expect(sessions.length, report.sessions);
    final first = sessions.first as Map<String, dynamic>;
    expect(first['started_at'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$')));
    expect((first['exercises'] as List<dynamic>), isNotEmpty);
    expect((json['readiness_days'] as List<dynamic>).length, greaterThan(80));

    final csv = await export.writeCsv(dir, now);
    expect(csv.length, 3);
    final setsFile = csv.firstWhere((f) => f.path.contains('spotter-sets-'));
    final lines = (await setsFile.readAsString()).split('\r\n').where((l) => l.isNotEmpty).toList();
    expect(lines.first, startsWith('session_id,session_started_at,session_exercise_id,exercise_id'));
    expect(lines.length, greaterThan(500));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
