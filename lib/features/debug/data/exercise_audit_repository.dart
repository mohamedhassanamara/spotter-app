import '../../../core/db/database.dart';
import '../../library/data/exercise_merger.dart';
import '../../library/domain/exercise_info.dart';
import '../../ranks/data/ranks_repository.dart';
import '../../tutorials/data/media_repository.dart';
import '../domain/exercise_audit.dart';

/// Gathers what the audit needs from the database: the exercises of my routines and history, the names I log them under, the
/// stored GIF matches, and the library's merge list.
class ExerciseAuditRepository {
  ExerciseAuditRepository(this._db);
  final AppDatabase _db;

  Future<List<AuditRow>> load(Map<String, ExerciseInfo> catalog) async {
    final routineExercises = await _db.select(_db.routineExercises).get();
    final routineIds = {for (final r in routineExercises) r.exerciseId};
    final names = <String, Set<String>>{};
    for (final r in routineExercises) {
      if (r.displayName != null) (names[r.exerciseId] ??= {}).add(r.displayName!);
    }
    final sessionExercises = await _db.select(_db.sessionExercises).get();
    final exerciseOf = {for (final se in sessionExercises) se.id: se.exerciseId};
    for (final se in sessionExercises) {
      if (se.displayName != null) (names[se.exerciseId] ??= {}).add(se.displayName!);
    }
    final setCounts = <String, int>{};
    for (final s in await _db.select(_db.workoutSets).get()) {
      if (!s.completed || s.isWarmup) continue;
      final id = exerciseOf[s.sessionExerciseId];
      if (id != null) setCounts[id] = (setCounts[id] ?? 0) + 1;
    }
    final matches = {for (final m in await _db.select(_db.mediaMatches).get()) m.exerciseId: (edbId: m.edbId, source: m.source)};
    final merges = await ExerciseMerger.loadAsset();
    return auditExercises(
      usedIds: {...routineIds, ...setCounts.keys},
      routineIds: routineIds,
      setCounts: setCounts,
      catalog: catalog,
      matches: matches,
      namesById: names,
      mergedCanonicals: {for (final m in merges) m.canonical: m.duplicate},
      edb: await MediaRepository.loadEdb(),
      standards: await RanksRepository.loadStandards(),
    );
  }
}
