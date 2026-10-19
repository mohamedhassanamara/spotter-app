import 'package:drift/drift.dart' show Variable;

import '../../features/import/data/liftoff_import_service.dart';
import 'database.dart';

/// One-time corrections to stored data, each guarded by a setting so it runs once.
class DataFixes {
  DataFixes._();

  static const lungeKey = 'fix_lunge_per_dumbbell_v1';
  static const lungeV2Key = 'fix_lunge_per_dumbbell_v2';
  static const lungeExerciseId = 'sp_db_walking_lunge';

  /// Liftoff logged Walking Lunge as the total of both dumbbells (35 kg); the app logs per dumbbell
  /// (17.5 kg). Halves every imported set of those exercises, once. In-app sets are untouched.
  static Future<int> ensureLungePerDumbbell(AppDatabase db) async {
    if (await db.getSetting(lungeKey) != null) return 0;
    final ids = liftoffTotalLoadIds.map((id) => "'$id'").join(',');
    final changed = await db.customUpdate(
      '''UPDATE workout_sets SET weight = weight / 2
         WHERE session_exercise_id IN (
           SELECT se.id FROM session_exercises se JOIN sessions s ON s.id = se.session_id
           WHERE se.exercise_id IN ($ids) AND s.source = '$liftoffSource')''',
      updates: {db.workoutSets},
    );
    await db.putSetting(lungeKey, '$changed');
    return changed;
  }

  /// Round 2: the first fix only touched imported sets, but the in-app Lower workouts logged after the import had
  /// followed the (total-load) history: 35 kg "per dumbbell", and the next suggestion was 37.5. A suggestion also
  /// stays frozen in a workout that was started before the fix. This halves what still looks like a total:
  /// - any non-imported Walking Lunge set heavier than 1.5 × the heaviest imported (converted) set, in finished and
  ///   in the active session, completed or not, with its suggested weight;
  /// - the stored suggestion of those exercise rows (weight and the "NN kg" figures in its text).
  /// Per-dumbbell sets the owner logged since (17.5 kg) are below the threshold and stay. Runs once.
  static Future<int> ensureLungeInAppSets(AppDatabase db) async {
    if (await db.getSetting(lungeV2Key) != null) return 0;
    await ensureLungePerDumbbell(db);
    final m = (await db.customSelect(
      '''SELECT MAX(w.weight) AS m FROM workout_sets w
         JOIN session_exercises se ON se.id = w.session_exercise_id JOIN sessions s ON s.id = se.session_id
         WHERE se.exercise_id = ? AND s.source = ?''',
      variables: [Variable.withString(lungeExerciseId), Variable.withString(liftoffSource)],
    ).getSingle())
        .read<double?>('m');
    var changed = 0;
    if (m != null && m > 0) {
      final limit = m * 1.5;
      final rows = await db.customSelect(
        '''SELECT w.id AS id, w.weight AS weight, w.suggested_weight AS sw FROM workout_sets w
           JOIN session_exercises se ON se.id = w.session_exercise_id JOIN sessions s ON s.id = se.session_id
           WHERE se.exercise_id = ? AND s.source <> ? AND (w.weight > ? OR w.suggested_weight > ?)''',
        variables: [Variable.withString(lungeExerciseId), Variable.withString(liftoffSource), Variable.withReal(limit), Variable.withReal(limit)],
      ).get();
      for (final r in rows) {
        final w = r.read<double>('weight'), sw = r.read<double?>('sw');
        await db.customUpdate(
          'UPDATE workout_sets SET weight = ?, suggested_weight = ? WHERE id = ?',
          variables: [Variable.withReal(w > limit ? _half(w) : w), sw == null ? const Variable<double>(null) : Variable.withReal(sw > limit ? _half(sw) : sw), Variable.withInt(r.read<int>('id'))],
          updates: {db.workoutSets},
        );
        changed++;
      }
      final exRows = await db.customSelect(
        '''SELECT se.id AS id, se.suggested_weight AS sw, se.suggestion_json AS j FROM session_exercises se JOIN sessions s ON s.id = se.session_id
           WHERE se.exercise_id = ? AND s.source <> ? AND (se.suggested_weight > ? OR se.suggestion_json LIKE '%kg%')''',
        variables: [Variable.withString(lungeExerciseId), Variable.withString(liftoffSource), Variable.withReal(limit)],
      ).get();
      for (final r in exRows) {
        final sw = r.read<double?>('sw');
        final json = r.read<String?>('j');
        final halvedWeight = sw != null && sw > limit;
        // Only a stored plan built from the total-load history is touched: its suggested weight was over the limit.
        if (!halvedWeight) continue;
        final text = json?.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?) kg'), (m) {
          final v = double.parse(m.group(1)!);
          return v > limit ? '${_fmt(_half(v))} kg' : m.group(0)!;
        });
        await db.customUpdate(
          'UPDATE session_exercises SET suggested_weight = ?, suggestion_json = ? WHERE id = ?',
          variables: [Variable.withReal(_half(sw)), text == null ? const Variable<String>(null) : Variable.withString(text), Variable.withInt(r.read<int>('id'))],
          updates: {db.sessionExercises},
        );
      }
    }
    await db.putSetting(lungeV2Key, '$changed');
    return changed;
  }

  /// Half of a total load, down to a dumbbell step (2.5 kg): 35 → 17.5, 37.5 → 17.5.
  static double _half(double total) => ((total / 2 / 2.5) + 1e-9).floorToDouble() * 2.5;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static Future<void> runAll(AppDatabase db) async {
    await ensureLungePerDumbbell(db);
    await ensureLungeInAppSets(db);
  }
}
