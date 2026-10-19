import 'dart:math' as math;

import '../../../core/domain/muscles.dart';
import '../../../core/domain/training.dart';

/// Weekly challenges. Pool of 24 (see [weeklyChallengePool]); three are picked each Monday. None of them depends on
/// following the coach's suggestions.
enum QuestKey {
  sessions,
  trainGroup,
  topOfRange,
  logRpe,
  newExercise,
  pr,
  workingSets,
  volume,
  warmups,
  greenDay,
  regions,
  toFailure,
  sleep,
  quickSession,
}

class QuestDef {
  const QuestDef({required this.key, required this.target, this.group});

  final QuestKey key;
  final int target;
  final BodyRegion? group;

  /// Identifies one pool entry (key + target + region), to avoid repeating last week's.
  String get id => '${key.name}:$target:${group?.name ?? ''}';

  String get title {
    switch (key) {
      case QuestKey.sessions:
        return 'Complete $target workouts this week';
      case QuestKey.trainGroup:
        return 'Train ${group!.label.toLowerCase()} ${target == 2 ? 'twice' : '$target times'}';
      case QuestKey.topOfRange:
        return 'Hit the top of your rep range on $target lifts';
      case QuestKey.logRpe:
        return 'Log your effort on every working set in $target workouts';
      case QuestKey.newExercise:
        return 'Try an exercise you have never logged';
      case QuestKey.pr:
        return target == 1 ? 'Set a personal record' : 'Set $target personal records';
      case QuestKey.workingSets:
        return 'Complete $target working sets';
      case QuestKey.volume:
        return 'Lift ${_thousands(target)} kg of total volume';
      case QuestKey.warmups:
        return 'Warm up before your lifts in $target workouts';
      case QuestKey.greenDay:
        return 'Train on a Green readiness day';
      case QuestKey.regions:
        return 'Train $target different body regions';
      case QuestKey.toFailure:
        return 'Take $target sets to failure';
      case QuestKey.sleep:
        return 'Sleep 7+ hours on $target nights';
      case QuestKey.quickSession:
        return 'Finish a workout in 75 minutes or less';
    }
  }

  static String _thousands(int n) => n >= 1000 ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}' : '$n';

  Map<String, Object?> toParams() => {'target': target, if (group != null) 'group': group!.name};

  /// Null for a key this version no longer has (the old "follow every suggestion" challenges).
  static QuestDef? tryFromParams(String key, Map<String, dynamic> params) {
    final k = QuestKey.values.where((e) => e.name == key).firstOrNull;
    if (k == null) return null;
    return QuestDef(
      key: k,
      target: (params['target'] as num).toInt(),
      group: params['group'] == null ? null : regionFromParam(params['group'] as String),
    );
  }

  static QuestDef fromParams(String key, Map<String, dynamic> params) =>
      tryFromParams(key, params) ?? (throw FormatException('Unknown quest $key'));
}

/// Keys of challenges that rewarded following suggestions; retired.
const retiredQuestKeys = ['followAll', 'noOverride'];

/// The pool the three weekly challenges come from (24 entries).
final List<QuestDef> weeklyChallengePool = [
  const QuestDef(key: QuestKey.sessions, target: 3),
  const QuestDef(key: QuestKey.sessions, target: 4),
  for (final r in const [BodyRegion.chest, BodyRegion.back, BodyRegion.legs, BodyRegion.shoulders, BodyRegion.arms, BodyRegion.core])
    QuestDef(key: QuestKey.trainGroup, target: 2, group: r),
  const QuestDef(key: QuestKey.topOfRange, target: 2),
  const QuestDef(key: QuestKey.topOfRange, target: 3),
  const QuestDef(key: QuestKey.logRpe, target: 3),
  const QuestDef(key: QuestKey.newExercise, target: 1),
  const QuestDef(key: QuestKey.pr, target: 1),
  const QuestDef(key: QuestKey.pr, target: 2),
  const QuestDef(key: QuestKey.workingSets, target: 60),
  const QuestDef(key: QuestKey.workingSets, target: 90),
  const QuestDef(key: QuestKey.volume, target: 15000),
  const QuestDef(key: QuestKey.volume, target: 25000),
  const QuestDef(key: QuestKey.warmups, target: 3),
  const QuestDef(key: QuestKey.greenDay, target: 1),
  const QuestDef(key: QuestKey.regions, target: 4),
  const QuestDef(key: QuestKey.toFailure, target: 5),
  const QuestDef(key: QuestKey.sleep, target: 5),
  const QuestDef(key: QuestKey.quickSession, target: 1),
];

/// Quests stored before v2.1 name one of the old 12 groups; map those to their region.
BodyRegion? regionFromParam(String name) =>
    BodyRegion.fromName(name) ??
    const {
      'biceps': BodyRegion.arms,
      'triceps': BodyRegion.arms,
      'forearms': BodyRegion.arms,
      'abs': BodyRegion.core,
      'quads': BodyRegion.legs,
      'hamstrings': BodyRegion.legs,
      'glutes': BodyRegion.legs,
      'calves': BodyRegion.legs,
      'traps': BodyRegion.back,
    }[name];

/// One exercise as performed in one session.
class ExerciseActivity {
  const ExerciseActivity({
    required this.exerciseId,
    required this.primaryRegions,
    required this.repMax,
    required this.sets,
    this.isNew = false,
  });
  final String exerciseId;
  final Set<BodyRegion> primaryRegions;
  final int repMax;
  final List<LoggedSet> sets;

  /// The first time this exercise was ever logged (with a working set).
  final bool isNew;

  List<LoggedSet> get working => sets.where((s) => s.isWorking).toList();
}

class SessionActivity {
  const SessionActivity({required this.date, required this.exercises, this.durationMinutes, this.readinessBand, this.prCount = 0});
  final DateTime date;
  final List<ExerciseActivity> exercises;
  final int? durationMinutes;

  /// Readiness band the workout started in ('green', 'yellow', 'red'), when known.
  final String? readinessBand;

  /// Valid PRs set in this workout.
  final int prCount;

  Iterable<LoggedSet> get workingSets => exercises.expand((e) => e.working);
  double get volume => workingSets.fold<double>(0, (v, s) => v + s.tonnage);
}

/// Everything a week's challenges are measured against.
class QuestWeek {
  const QuestWeek({required this.sessions, this.sleepNights = 0});
  final List<SessionActivity> sessions;

  /// Nights this week with 7+ hours of sleep (Apple Health).
  final int sleepNights;
}

class QuestGenInput {
  const QuestGenInput({
    required this.weekStart,
    this.recentIds = const {},
    this.exclude = const {},
    this.hasSleepData = false,
    this.hasReadinessData = false,
  });

  final DateTime weekStart;

  /// Ids ([QuestDef.id]) of last week's challenges: not picked again.
  final Set<String> recentIds;

  /// Kinds already present this week (when topping up).
  final Set<QuestKey> exclude;
  final bool hasSleepData;
  final bool hasReadinessData;
}

class QuestEngine {
  const QuestEngine();

  /// Three challenges for the week of [QuestGenInput.weekStart], picked from the pool. Deterministic for a given
  /// Monday (the same week always gives the same three), never two of a kind, nothing from last week, and
  /// nothing that needs data the lifter doesn't have (sleep, readiness).
  List<QuestDef> generate(QuestGenInput input, {int count = 3}) {
    final week = DateTime.utc(input.weekStart.year, input.weekStart.month, input.weekStart.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay ~/ 7;
    final rng = math.Random(week * 7919 + 13);
    final pool = [
      for (final q in weeklyChallengePool)
        if (!(q.key == QuestKey.sleep && !input.hasSleepData) && !(q.key == QuestKey.greenDay && !input.hasReadinessData)) q,
    ]..shuffle(rng);
    final fresh = [for (final q in pool) if (!input.recentIds.contains(q.id)) q];
    final ordered = [...fresh, for (final q in pool) if (input.recentIds.contains(q.id)) q];
    final picked = <QuestDef>[];
    final kinds = {...input.exclude};
    for (final q in ordered) {
      if (kinds.contains(q.key)) continue;
      picked.add(q);
      kinds.add(q.key);
      if (picked.length == count) break;
    }
    return picked;
  }

  /// Progress towards [quest] from the data of its week.
  int progress(QuestDef quest, QuestWeek week) {
    final sessions = week.sessions;
    switch (quest.key) {
      case QuestKey.sessions:
        return sessions.length;
      case QuestKey.trainGroup:
        return sessions.where((s) => s.exercises.any((e) => e.primaryRegions.contains(quest.group) && e.working.isNotEmpty)).length;
      case QuestKey.topOfRange:
        final lifts = <String>{};
        for (final s in sessions) {
          for (final e in s.exercises) {
            final w = e.working;
            if (w.isNotEmpty && w.every((x) => x.reps >= e.repMax)) lifts.add(e.exerciseId);
          }
        }
        return lifts.length;
      case QuestKey.logRpe:
        return sessions.where((s) {
          final w = s.workingSets.toList();
          return w.isNotEmpty && w.every((x) => x.rpe != null);
        }).length;
      case QuestKey.newExercise:
        return {for (final s in sessions) for (final e in s.exercises) if (e.isNew && e.working.isNotEmpty) e.exerciseId}.length;
      case QuestKey.pr:
        return sessions.fold<int>(0, (n, s) => n + s.prCount);
      case QuestKey.workingSets:
        return sessions.fold<int>(0, (n, s) => n + s.workingSets.length);
      case QuestKey.volume:
        return sessions.fold<double>(0, (v, s) => v + s.volume).round();
      case QuestKey.warmups:
        return sessions.where((s) => s.exercises.any((e) => e.sets.any((x) => x.isWarmup && x.completed))).length;
      case QuestKey.greenDay:
        return sessions.where((s) => s.readinessBand == 'green' && s.workingSets.isNotEmpty).length;
      case QuestKey.regions:
        return {for (final s in sessions) for (final e in s.exercises) if (e.working.isNotEmpty) ...e.primaryRegions}.length;
      case QuestKey.toFailure:
        return sessions.fold<int>(0, (n, s) => n + s.workingSets.where((x) => x.rpe != null && x.rpe! >= 9.9).length);
      case QuestKey.sleep:
        return week.sleepNights;
      case QuestKey.quickSession:
        return sessions.where((s) => s.workingSets.isNotEmpty && s.durationMinutes != null && s.durationMinutes! <= 75).length;
    }
  }
}

/// Average finished sessions per week over the 4 weeks before [now] (at least 1).
int sessionsPerWeekLast4(Iterable<DateTime> sessionStarts, DateTime now) {
  final from = now.subtract(const Duration(days: 28));
  final n = sessionStarts.where((d) => d.isAfter(from) && !d.isAfter(now)).length;
  return (n / 4).round().clamp(1, 14);
}
