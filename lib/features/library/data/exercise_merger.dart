import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/db/database.dart';
import '../../coach/data/gym_repository.dart';
import '../../ranks/data/rank_exclusions.dart';

/// One library entry that is really another exercise.
class ExerciseMerge {
  const ExerciseMerge({required this.duplicate, required this.canonical, this.canonicalName, this.reason = ''});
  final String duplicate;
  final String canonical;

  /// Renames the canonical exercise (the name the app logs it under).
  final String? canonicalName;
  final String reason;

  static List<ExerciseMerge> parse(String json) => [
        for (final m in (jsonDecode(json) as Map<String, dynamic>)['merges'] as List<dynamic>)
          ExerciseMerge(
            duplicate: (m as Map<String, dynamic>)['duplicate'] as String,
            canonical: m['canonical'] as String,
            canonicalName: m['canonical_name'] as String?,
            reason: m['reason'] as String? ?? '',
          ),
      ];
}

/// What a merge did, for the log and the report.
class MergeResult {
  const MergeResult({required this.merge, required this.historyRows, required this.routineRows, required this.duplicateName, required this.canonicalName});
  final ExerciseMerge merge;

  /// Session exercises (history) and routine rows moved to the canonical exercise.
  final int historyRows;
  final int routineRows;
  final String duplicateName;
  final String canonicalName;
}

/// Merges duplicate library entries into one canonical exercise: history, routines, "counts toward rank",
/// gym overrides, form resets, favourites and media all move to the canonical id and the duplicate row is
/// removed. Idempotent and cheap when there is nothing to merge, so it runs on every start (the library
/// re-seeds on dataset bumps) and after an import.
class ExerciseMerger {
  ExerciseMerger(this._db);
  final AppDatabase _db;

  static const assetPath = 'assets/exercise_merges.json';
  static const logKey = 'exercise_merges_log';

  static Future<List<ExerciseMerge>> loadAsset() async => ExerciseMerge.parse(await rootBundle.loadString(assetPath));

  /// Applies [merges] (the bundled list by default). Returns what changed.
  Future<List<MergeResult>> apply({List<ExerciseMerge>? merges}) async {
    final list = merges ?? await loadAsset();
    final existing = {for (final r in await _db.customSelect('SELECT id, name FROM exercises').get()) r.read<String>('id'): r.read<String>('name')};
    final results = <MergeResult>[];
    await _db.transaction(() async {
      for (final m in list) {
        final canonName = existing[m.canonical];
        if (canonName == null) continue; // not in this install's library (e.g. an import custom not made yet)
        if (m.canonicalName != null && canonName != m.canonicalName) {
          await _db.customUpdate('UPDATE exercises SET name = ? WHERE id = ?',
              variables: [Variable.withString(m.canonicalName!), Variable.withString(m.canonical)], updates: {_db.exercises});
          existing[m.canonical] = m.canonicalName!;
        }
        final dupName = existing[m.duplicate];
        if (dupName == null) continue;
        results.add(await _mergeOne(m, dupName, existing[m.canonical]!));
        existing.remove(m.duplicate);
      }
    });
    if (results.isNotEmpty) {
      final old = jsonDecode(await _db.getSetting(logKey) ?? '[]') as List<dynamic>;
      await _db.putSetting(
        logKey,
        jsonEncode([
          ...old,
          for (final r in results)
            {
              'duplicate': r.merge.duplicate,
              'duplicate_name': r.duplicateName,
              'canonical': r.merge.canonical,
              'canonical_name': r.canonicalName,
              'history_rows': r.historyRows,
              'routine_rows': r.routineRows,
            },
        ]),
      );
    }
    return results;
  }

  Future<MergeResult> _mergeOne(ExerciseMerge m, String dupName, String canonName) async {
    final dup = Variable.withString(m.duplicate), canon = Variable.withString(m.canonical);
    final hist = await _count('session_exercises', m.duplicate);
    final routine = await _count('routine_exercises', m.duplicate);

    // What the logs called it stays: sessions without their own name keep the duplicate's.
    await _db.customUpdate('UPDATE session_exercises SET display_name = ? WHERE exercise_id = ? AND display_name IS NULL',
        variables: [Variable.withString(dupName), dup], updates: {_db.sessionExercises});
    for (final table in const ['session_exercises', 'routine_exercises', 'ego_freezes']) {
      await _db.customUpdate('UPDATE $table SET exercise_id = ? WHERE exercise_id = ?', variables: [canon, dup]);
    }
    // One row per exercise: the canonical's wins, the duplicate's is only used when it has none.
    for (final table in const ['media_matches', 'pinned_videos', 'edb_v2_maps']) {
      await _db.customUpdate('UPDATE OR IGNORE $table SET exercise_id = ? WHERE exercise_id = ?', variables: [canon, dup]);
      await _db.customUpdate('DELETE FROM $table WHERE exercise_id = ?', variables: [dup]);
    }
    await _carryOver(m);
    await _rekeySettings(m);
    await _db.customUpdate('DELETE FROM exercises WHERE id = ?', variables: [dup], updates: {_db.exercises});
    return MergeResult(merge: m, historyRows: hist, routineRows: routine, duplicateName: dupName, canonicalName: canonName);
  }

  Future<int> _count(String table, String id) async =>
      (await _db.customSelect('SELECT COUNT(*) AS n FROM $table WHERE exercise_id = ?', variables: [Variable.withString(id)]).getSingle()).read<int>('n');

  /// Favourite, demo images, ExerciseDB id and instructions the canonical lacks.
  Future<void> _carryOver(ExerciseMerge m) async {
    final dup = await (_db.select(_db.exercises)..where((t) => t.id.equals(m.duplicate))).getSingle();
    final canon = await (_db.select(_db.exercises)..where((t) => t.id.equals(m.canonical))).getSingle();
    List<String> list(String raw) => (jsonDecode(raw) as List<dynamic>).cast<String>();
    final extra = {...list(canon.extraImages), ...list(dup.extraImages)}.toList();
    await (_db.update(_db.exercises)..where((t) => t.id.equals(m.canonical))).write(ExercisesCompanion(
      isFavorite: Value(canon.isFavorite || dup.isFavorite),
      images: list(canon.images).isEmpty && list(dup.images).isNotEmpty ? Value(dup.images) : const Value.absent(),
      extraImages: Value(jsonEncode(extra)),
      edbV1Id: canon.edbV1Id == null && dup.edbV1Id != null ? Value(dup.edbV1Id) : const Value.absent(),
      instructions: list(canon.instructions).isEmpty && list(dup.instructions).isNotEmpty ? Value(dup.instructions) : const Value.absent(),
      notes: (canon.notes ?? '').isEmpty && (dup.notes ?? '').isNotEmpty ? Value(dup.notes) : const Value.absent(),
    ));
  }

  /// Settings that are keyed by exercise id.
  Future<void> _rekeySettings(ExerciseMerge m) async {
    final d = m.duplicate, c = m.canonical;

    final manual = await _db.getSetting(RankExclusions.manualKey);
    if (manual != null) {
      final map = (jsonDecode(manual) as Map<String, dynamic>);
      if (map.containsKey(d)) {
        final v = map.remove(d);
        map.putIfAbsent(c, () => v); // the canonical's own choice wins
        await _db.putSetting(RankExclusions.manualKey, jsonEncode(map));
      }
    }
    final auto = await _db.getSetting(RankExclusions.autoKey);
    if (auto != null) {
      final ids = (jsonDecode(auto) as List<dynamic>).cast<String>().toList();
      if (ids.remove(d)) {
        if (!ids.contains(c)) ids.add(c);
        await _db.putSetting(RankExclusions.autoKey, jsonEncode(ids..sort()));
      }
    }
    final gym = await _db.getSetting('gym_equipment');
    if (gym != null) {
      final j = jsonDecode(gym) as Map<String, dynamic>;
      var changed = false;
      for (final key in const ['type_overrides', 'per_exercise', 'max_loads']) {
        final map = j[key] as Map<String, dynamic>?;
        if (map != null && map.containsKey(d)) {
          final v = map.remove(d);
          map.putIfAbsent(c, () => v);
          changed = true;
        }
      }
      if (changed) await _db.putSetting('gym_equipment', jsonEncode(j));
    }
    final resets = await _db.getSetting(GymRepository.formResetsKey);
    if (resets != null) {
      final map = jsonDecode(resets) as Map<String, dynamic>;
      if (map.containsKey(d)) {
        final v = map.remove(d);
        map.putIfAbsent(c, () => v);
        await _db.putSetting(GymRepository.formResetsKey, jsonEncode(map));
      }
    }
  }
}
