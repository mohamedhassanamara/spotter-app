import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../../core/settings/app_settings.dart';
import '../../gamification/domain/achievements.dart';
import '../../gamification/domain/streaks.dart';
import '../../library/domain/exercise_info.dart';
import '../../library/domain/load_kinds.dart';
import '../../ranks/data/rank_exclusions.dart';
import '../../workout/data/finish_service.dart';
import '../domain/liftoff.dart';
import '../domain/liftoff_mapping.dart';

const liftoffSource = 'liftoff';

/// Setting written on the first successful import (ISO date). The day streak's starting offset is
/// anchored to it.
const liftoffImportedAtKey = 'liftoff_imported_at';

/// The owner's Liftoff day streak on the day of the import (section 4). It becomes a
/// [StreakOffset] on the first import; Settings → Streak can change it.
const int liftoffStreakDays = 177;

/// What an import would do, shown before anything is written.
class LiftoffPreview {
  const LiftoffPreview({
    required this.parse,
    required this.mappings,
    required this.newSessions,
    required this.alreadyImported,
  });

  final LiftoffParse parse;
  final List<NameMapping> mappings;

  /// Sessions not imported before (by their Liftoff Date).
  final List<LiftoffSession> newSessions;
  final int alreadyImported;

  int get newSets => newSessions.fold<int>(0, (a, s) => a + s.setCount);
  DateTime? get first => parse.sessions.isEmpty ? null : parse.sessions.first.start;
  DateTime? get last => parse.sessions.isEmpty ? null : parse.sessions.last.start;
  List<NameMapping> get unmatched => [for (final m in mappings) if (m.method == MatchMethod.unmatched) m];
  List<NameMapping> get toReview => [for (final m in mappings) if (m.needsReview) m];
  NameMapping mappingFor(String name) => mappings.firstWhere((m) => m.liftoffName == name);
}

class LiftoffImportResult {
  const LiftoffImportResult({required this.sessions, required this.sets, required this.customsCreated, required this.achievements});
  final int sessions;
  final int sets;
  final int customsCreated;
  final List<AchievementDef> achievements;
}

class LiftoffImportService {
  LiftoffImportService(this._db);
  final AppDatabase _db;

  static Future<LiftoffNameMap> loadNameMap() async =>
      LiftoffNameMap.parse(await rootBundle.loadString('assets/liftoff_name_map.json'));

  Future<List<RoutineName>> _routineNames(Map<String, ExerciseInfo> catalog) async {
    final rows = await _db.select(_db.routineExercises).get();
    return [
      for (final r in rows) RoutineName(name: r.displayName ?? catalog[r.exerciseId]?.name ?? r.exerciseId, exerciseId: r.exerciseId),
    ];
  }

  Future<LiftoffPreview> preview(
    String csv, {
    required Map<String, ExerciseInfo> catalog,
    LiftoffNameMap? nameMap,
    Map<String, String> manual = const {},
  }) async {
    final parse = parseLiftoff(csv);
    final setsByName = <String, int>{};
    for (final s in parse.sessions) {
      for (final e in s.exercises) {
        setsByName[e.name] = (setsByName[e.name] ?? 0) + e.sets.length;
      }
    }
    final mappings = mapLiftoffNames(
      setsByName: setsByName,
      catalog: catalog,
      nameMap: nameMap ?? await loadNameMap(),
      routines: await _routineNames(catalog),
      manual: manual,
    );
    final existing = (await (_db.select(_db.sessions)..where((t) => t.source.equals(liftoffSource))).get())
        .map((s) => s.externalId)
        .toSet();
    final fresh = [for (final s in parse.sessions) if (!existing.contains(s.key)) s];
    return LiftoffPreview(
      parse: parse,
      mappings: mappings,
      newSessions: fresh,
      alreadyImported: parse.sessions.length - fresh.length,
    );
  }

  /// Writes the preview's new sessions as finished, imported sessions. Idempotent: a session whose
  /// Liftoff Date is already in the database is skipped. Imported sets are logged as taken to
  /// failure (RPE 10) unless the file has an RPE, carry no suggestion (so they never count for
  /// discipline or overrides) and earn no XP. Achievements are re-evaluated afterwards.
  Future<LiftoffImportResult> commit(
    LiftoffPreview preview, {
    required Map<String, ExerciseInfo> catalog,
    required SettingsModel settings,
    required DateTime now,
  }) async {
    final mapping = {for (final m in preview.mappings) m.liftoffName: m};
    final routines = await _routineExerciseSets();
    var sessions = 0, sets = 0, customs = 0;

    await _db.transaction(() async {
      // Custom exercises for names the library doesn't have.
      for (final m in preview.mappings) {
        final c = m.custom;
        if (c == null || catalog.containsKey(m.exerciseId)) continue;
        customs += await _db.into(_db.exercises).insert(
              ExercisesCompanion.insert(
                id: m.exerciseId!,
                name: c.name,
                primaryMuscles: Value(jsonEncode(c.primaryMuscles)),
                secondaryMuscles: Value(jsonEncode(c.secondaryMuscles)),
                equipment: Value(c.equipment),
                mechanic: Value(c.compound ? 'compound' : 'isolation'),
                category: const Value('strength'),
                isCustom: const Value(true),
                notes: const Value('Created by the Liftoff import.'),
              ),
              mode: InsertMode.insertOrIgnore,
            ) >
            0
            ? 1
            : 0;
      }

      for (final s in preview.newSessions) {
        final already = await (_db.select(_db.sessions)
              ..where((t) => t.source.equals(liftoffSource) & t.externalId.equals(s.key)))
            .getSingleOrNull();
        if (already != null) continue;
        final resolved = [
          for (final e in s.exercises) mapping[e.name]!.resolveFor(e.sets.map((x) => x.weightKg).reduce(math.max)),
        ];
        final ids = [for (final r in resolved) r.$1];
        final routine = _guessRoutine(ids, routines);
        final sessionId = await _db.into(_db.sessions).insert(SessionsCompanion.insert(
              name: routine?.$2 ?? 'Liftoff workout',
              routineId: Value(routine?.$1),
              startedAt: s.start,
              endedAt: Value(s.end),
              status: const Value('finished'),
              notes: const Value('Imported from Liftoff'),
              source: const Value(liftoffSource),
              externalId: Value(s.key),
            ));
        sessions++;
        final total = math.max(1, s.setCount);
        var setIndex = 0;
        for (var i = 0; i < s.exercises.length; i++) {
          final e = s.exercises[i];
          final scheme = e.scheme;
          final reps = [for (var j = 0; j < e.sets.length; j++) scheme.repsFor(j, e.sets[j].reps)];
          final observed = RepRange(reps.reduce(math.min), reps.reduce(math.max));
          final first = scheme.rangeFor(0) ?? observed;
          final (exerciseId, displayName) = resolved[i];
          final assisted = isAssisted(exerciseId) || isLiftoffAssisted(e.name);
          final exId = await _db.into(_db.sessionExercises).insert(SessionExercisesCompanion.insert(
                sessionId: sessionId,
                exerciseId: exerciseId,
                position: i,
                repMin: first.min,
                repMax: first.max,
                targetSets: e.sets.length,
                restSeconds: 120,
                targetRir: const Value(0),
                notes: Value(e.sets.map((x) => x.note).firstWhere((n) => n.isNotEmpty, orElse: () => '')),
                displayName: Value(displayName),
              ));
          for (var j = 0; j < e.sets.length; j++) {
            final x = e.sets[j];
            final target = scheme.rangeFor(j);
            await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
                  sessionExerciseId: exId,
                  position: j,
                  weight: Value(assisted ? -x.weightKg.abs() : x.weightKg),
                  reps: Value(scheme.repsFor(j, x.reps)),
                  rpe: Value(x.rpe ?? 10),
                  completed: const Value(true),
                  // Liftoff only keeps the session start and length; spread the sets across it.
                  completedAt: Value(s.start.add(s.duration * ((setIndex + 1) / total))),
                  targetRepMin: Value(target?.min),
                  targetRepMax: Value(target?.max),
                  targetRir: const Value(0),
                ));
            setIndex++;
            sets++;
          }
        }
      }
      final excluded = {for (final m in preview.mappings) if (m.excludeFromRanks) m.exerciseId!};
      if (excluded.isNotEmpty) await RankExclusions(_db).addAll(excluded);
      if (sessions > 0 && await _db.getSetting(liftoffImportedAtKey) == null) {
        await _db.putSetting(liftoffImportedAtKey, now.toIso8601String());
        if (await _db.getSetting(StreakOffset.settingKey) == null) {
          await _db.putSetting(StreakOffset.settingKey, StreakOffset(date: now, days: liftoffStreakDays).encode());
        }
      }
    });

    final achievements = sessions == 0
        ? const <AchievementDef>[]
        : await FinishService(_db).reevaluateAchievements(
            now: now,
            catalog: {...catalog, for (final e in await _db.select(_db.exercises).get()) e.id: _info(e, catalog)},
            settings: settings,
          );
    return LiftoffImportResult(sessions: sessions, sets: sets, customsCreated: customs, achievements: achievements);
  }

  static ExerciseInfo _info(Exercise e, Map<String, ExerciseInfo> catalog) =>
      catalog[e.id] ??
      ExerciseInfo(
        id: e.id,
        name: e.name,
        primaryMuscles: (jsonDecode(e.primaryMuscles) as List).cast<String>(),
        secondaryMuscles: (jsonDecode(e.secondaryMuscles) as List).cast<String>(),
        equipment: e.equipment,
        level: e.level,
        mechanic: e.mechanic,
        category: e.category,
        instructions: const [],
        images: const [],
        isCustom: e.isCustom,
        isFavorite: e.isFavorite,
        notes: e.notes,
      );

  Future<List<(int, String, Set<String>)>> _routineExerciseSets() async {
    final routines = await _db.select(_db.routines).get();
    final rows = await _db.select(_db.routineExercises).get();
    return [
      for (final r in routines) (r.id, r.name, {for (final x in rows) if (x.routineId == r.id) x.exerciseId}),
    ];
  }

  /// The routine sharing most exercises with the session, if at least half of them.
  static (int, String)? _guessRoutine(List<String> ids, List<(int, String, Set<String>)> routines) {
    (int, String)? best;
    var bestHits = 0;
    for (final (id, name, set) in routines) {
      final hits = ids.where(set.contains).length;
      if (hits > bestHits) {
        bestHits = hits;
        best = (id, name);
      }
    }
    return bestHits * 2 >= ids.length && bestHits > 0 ? best : null;
  }
}
