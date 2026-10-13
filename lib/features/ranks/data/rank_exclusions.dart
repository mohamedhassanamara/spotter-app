import 'dart:convert';


import '../../../core/db/database.dart';

/// Where an exercise's "Counts toward rank" switch comes from.
enum RankSource { manualOn, manualOff, routine, auto, off }

/// Which exercises feed ranks. An exercise counts when:
/// 1. you switched it on or off by hand (manual always wins), else
/// 2. it is in one of your current routines, else
/// 3. you completed a working set of it in an in-app workout (automatic), else it is off.
/// Imported (Liftoff) history never switches anything on. Their sets stay in history and PRs either way.
class RankPolicy {
  const RankPolicy({this.manual = const {}, this.auto = const {}, this.routineIds = const {}});

  /// Exercise id → true (switched on by hand) / false (switched off by hand).
  final Map<String, bool> manual;

  /// Switched on by a completed in-app working set.
  final Set<String> auto;
  final Set<String> routineIds;

  RankSource sourceOf(String id) {
    final m = manual[id];
    if (m != null) return m ? RankSource.manualOn : RankSource.manualOff;
    if (routineIds.contains(id)) return RankSource.routine;
    if (auto.contains(id)) return RankSource.auto;
    return RankSource.off;
  }

  bool isOn(String id) => switch (sourceOf(id)) {
        RankSource.manualOn || RankSource.routine || RankSource.auto => true,
        RankSource.manualOff || RankSource.off => false,
      };
}

class RankExclusions {
  RankExclusions(this._db);
  final AppDatabase _db;

  /// Before the routine rule: the exercises hidden from ranks. Read once by [ensureMigrated].
  static const legacyKey = 'rank_excluded_exercises';
  static const manualKey = 'rank_manual';
  static const autoKey = 'rank_auto_on';
  static const migratedKey = 'rank_policy_v2';

  static Set<String> _decodeSet(String? raw) => raw == null ? {} : {...(jsonDecode(raw) as List<dynamic>).cast<String>()};

  static Map<String, bool> _decodeManual(String? raw) =>
      raw == null ? {} : {for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries) e.key: e.value as bool};

  Future<Set<String>> _routineIds() async =>
      {for (final r in await _db.select(_db.routineExercises).get()) r.exerciseId};

  Future<RankPolicy> policy() async => RankPolicy(
        manual: _decodeManual(await _db.getSetting(manualKey)),
        auto: _decodeSet(await _db.getSetting(autoKey)),
        routineIds: await _routineIds(),
      );

  /// Every exercise that does NOT count toward ranks (the whole library minus [RankPolicy.isOn]).
  Future<Set<String>> load() async {
    final p = await policy();
    final ids = (await _db.customSelect('SELECT id FROM exercises').get()).map((r) => r.read<String>('id'));
    return {for (final id in ids) if (!p.isOn(id)) id};
  }

  /// Re-emits when settings or the routines change.
  Stream<Set<String>> watch() => _db
      .customSelect('SELECT 1', readsFrom: {_db.appSettings, _db.routineExercises, _db.exercises})
      .watch()
      .asyncMap((_) => load());

  Future<void> _putManual(Map<String, bool> m) => _db.putSetting(manualKey, jsonEncode(m));

  /// The switch on the muscle sheet, the Ranks tab and the exercise page: a manual choice.
  Future<void> set(String id, {required bool excluded}) async {
    final m = _decodeManual(await _db.getSetting(manualKey));
    m[id] = !excluded;
    await _putManual(m);
  }

  /// A completed in-app working set switches the exercise on, unless you chose by hand.
  Future<void> autoEnable(String id) async {
    if (_decodeManual(await _db.getSetting(manualKey)).containsKey(id)) return;
    final auto = _decodeSet(await _db.getSetting(autoKey));
    if (auto.add(id)) await _db.putSetting(autoKey, jsonEncode(auto.toList()..sort()));
  }

  /// One time: exercises you had hidden that are in a routine stay off (by hand); exercises you did in
  /// in-app workouts are switched on (automatic). Everything else follows the routine rule.
  static Future<void> ensureMigrated(AppDatabase db) async {
    if (await db.getSetting(migratedKey) != null) return;
    final repo = RankExclusions(db);
    final legacy = _decodeSet(await db.getSetting(legacyKey));
    final inRoutines = await repo._routineIds();
    final manual = _decodeManual(await db.getSetting(manualKey));
    for (final id in legacy) {
      if (inRoutines.contains(id)) manual.putIfAbsent(id, () => false);
    }
    final done = await db.customSelect('''
      SELECT DISTINCT se.exercise_id AS id FROM workout_sets w
      JOIN session_exercises se ON se.id = w.session_exercise_id
      JOIN sessions s ON s.id = se.session_id
      WHERE s.source = 'app' AND w.completed = 1 AND w.is_warmup = 0 AND w.set_type IS NULL AND w.reps > 0
    ''').get();
    final auto = {for (final r in done) r.read<String>('id')}..removeAll(manual.keys);
    await repo._putManual(manual);
    await db.putSetting(autoKey, jsonEncode(auto.toList()..sort()));
    await db.putSetting(migratedKey, DateTime.now().toIso8601String());
  }
}
