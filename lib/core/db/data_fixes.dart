import '../../features/import/data/liftoff_import_service.dart';
import 'database.dart';

/// One-time corrections to stored data, each guarded by a setting so it runs once.
class DataFixes {
  DataFixes._();

  static const lungeKey = 'fix_lunge_per_dumbbell_v1';

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

  static Future<void> runAll(AppDatabase db) async {
    await ensureLungePerDumbbell(db);
  }
}
