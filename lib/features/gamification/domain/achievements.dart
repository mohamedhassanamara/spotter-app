/// Achievement metric types understood by [AchievementEvaluator]. Definitions live in `assets/achievements.json`.
/// None of them may depend on following the coach's suggestions.
enum AchievementType {
  sessions,

  /// Longest day streak (no more than two rest days in a row).
  streakDays,
  prs,
  totalVolumeKg,
  totalSets,
  maxSessionVolumeKg,
  level,

  /// Best ranked lift, as a tier index (0 = Iron … 8 = Immortal).
  bestExerciseTier,
  overallTier,

  /// Muscles at or above the tier index in [AchievementDef.param].
  musclesAtTier,

  /// Body regions at or above the tier index in [AchievementDef.param] (0 = just ranked).
  regionsAtTier,
  musclesRanked,
  distinctExercises,

  /// Workouts started on a Green readiness day.
  greenSessions,

  /// Longest run of nights with 7+ hours of sleep (Apple Health).
  sleepStreak,

  /// Weeks in which every one of your routines was done.
  fullProgramWeeks,
}

enum AchievementCategory {
  consistency('Consistency'),
  strength('Strength'),
  volume('Volume'),
  exploration('Exploration'),
  recovery('Recovery & readiness'),
  program('Program');

  const AchievementCategory(this.label);
  final String label;
}

/// Bronze, silver or gold step of a family (e.g. 25 / 100 / 250 workouts).
enum AchievementLevel {
  bronze('Bronze'),
  silver('Silver'),
  gold('Gold');

  const AchievementLevel(this.label);
  final String label;
}

class AchievementDef {
  const AchievementDef({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
    required this.threshold,
    this.category = AchievementCategory.consistency,
    this.family,
    this.level,
    this.param,
  });

  final String key;
  final String title;
  final String description;
  final String icon;
  final AchievementType type;
  final double threshold;
  final AchievementCategory category;

  /// Name of the family this is a step of, with its [level]; null for one-off achievements.
  final String? family;
  final AchievementLevel? level;

  /// Extra parameter of the metric (the tier index for [AchievementType.musclesAtTier] / [AchievementType.regionsAtTier]).
  final int? param;

  /// Rank-derived: can be re-checked (and silently revoked) when the rank model changes.
  bool get isRankBased => const {
        AchievementType.bestExerciseTier,
        AchievementType.overallTier,
        AchievementType.musclesAtTier,
        AchievementType.regionsAtTier,
        AchievementType.musclesRanked,
      }.contains(type);

  factory AchievementDef.fromJson(Map<String, dynamic> j) {
    final typeName = j['type'] as String;
    final type = AchievementType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => throw FormatException('Unknown achievement type $typeName'),
    );
    return AchievementDef(
      key: j['key'] as String,
      title: j['title'] as String,
      description: j['description'] as String,
      icon: j['icon'] as String? ?? 'star',
      type: type,
      threshold: (j['threshold'] as num).toDouble(),
      category: AchievementCategory.values.firstWhere((c) => c.name == j['category'], orElse: () => AchievementCategory.consistency),
      family: j['family'] as String?,
      level: j['level'] == null ? null : AchievementLevel.values.firstWhere((l) => l.name == j['level']),
      param: (j['param'] as num?)?.toInt(),
    );
  }
}

/// Aggregated lifetime stats the achievements are checked against.
class AchievementStats {
  const AchievementStats({
    this.sessions = 0,
    this.longestStreakDays = 0,
    this.prs = 0,
    this.totalVolumeKg = 0,
    this.totalSets = 0,
    this.maxSessionVolumeKg = 0,
    this.level = 1,
    this.bestExerciseTierIndex = -1,
    this.overallTierIndex = -1,
    this.muscleTierIndexes = const [],
    this.regionTierIndexes = const [],
    this.distinctExercises = 0,
    this.greenSessions = 0,
    this.longestSleepStreak = 0,
    this.fullProgramWeeks = 0,
  });

  final int sessions;
  final int longestStreakDays;
  final int prs;
  final double totalVolumeKg;
  final int totalSets;
  final double maxSessionVolumeKg;
  final int level;
  final int bestExerciseTierIndex;
  final int overallTierIndex;

  /// Tier index of every ranked muscle / body region (unranked ones are absent).
  final List<int> muscleTierIndexes;
  final List<int> regionTierIndexes;
  final int distinctExercises;
  final int greenSessions;
  final int longestSleepStreak;
  final int fullProgramWeeks;

  double valueFor(AchievementDef d) {
    switch (d.type) {
      case AchievementType.sessions:
        return sessions.toDouble();
      case AchievementType.streakDays:
        return longestStreakDays.toDouble();
      case AchievementType.prs:
        return prs.toDouble();
      case AchievementType.totalVolumeKg:
        return totalVolumeKg;
      case AchievementType.totalSets:
        return totalSets.toDouble();
      case AchievementType.maxSessionVolumeKg:
        return maxSessionVolumeKg;
      case AchievementType.level:
        return level.toDouble();
      case AchievementType.bestExerciseTier:
        return bestExerciseTierIndex.toDouble();
      case AchievementType.overallTier:
        return overallTierIndex.toDouble();
      case AchievementType.musclesAtTier:
        return muscleTierIndexes.where((t) => t >= (d.param ?? 0)).length.toDouble();
      case AchievementType.regionsAtTier:
        return regionTierIndexes.where((t) => t >= (d.param ?? 0)).length.toDouble();
      case AchievementType.musclesRanked:
        return muscleTierIndexes.length.toDouble();
      case AchievementType.distinctExercises:
        return distinctExercises.toDouble();
      case AchievementType.greenSessions:
        return greenSessions.toDouble();
      case AchievementType.sleepStreak:
        return longestSleepStreak.toDouble();
      case AchievementType.fullProgramWeeks:
        return fullProgramWeeks.toDouble();
    }
  }
}

class AchievementEvaluator {
  const AchievementEvaluator();

  bool isMet(AchievementDef def, AchievementStats stats) => stats.valueFor(def) >= def.threshold;

  /// 0..1 progress for display.
  double progress(AchievementDef def, AchievementStats stats) {
    if (def.threshold <= 0) return isMet(def, stats) ? 1 : 0;
    return (stats.valueFor(def) / def.threshold).clamp(0.0, 1.0);
  }

  List<AchievementDef> newlyUnlocked(List<AchievementDef> defs, AchievementStats stats, Set<String> alreadyUnlocked) =>
      [for (final d in defs) if (!alreadyUnlocked.contains(d.key) && isMet(d, stats)) d];
}

/// Longest run of consecutive days with at least [minMinutes] of sleep. [sleepMinutesByDay] maps a day index
/// (any consistent integer day number) to minutes slept that night.
int longestSleepStreak(Map<int, double> sleepMinutesByDay, {double minMinutes = 420}) {
  final days = [for (final e in sleepMinutesByDay.entries) if (e.value >= minMinutes) e.key]..sort();
  var best = 0, run = 0;
  int? last;
  for (final d in days) {
    run = last != null && d == last + 1 ? run + 1 : 1;
    if (run > best) best = run;
    last = d;
  }
  return best;
}

/// Weeks (Monday-based week numbers) in which every routine in [routineIds] was done at least once.
/// [sessionRoutines] is (week number, routine id) per finished session.
int fullProgramWeeks(Iterable<(int week, int? routineId)> sessionRoutines, Set<int> routineIds) {
  if (routineIds.isEmpty) return 0;
  final byWeek = <int, Set<int>>{};
  for (final (week, routine) in sessionRoutines) {
    if (routine != null && routineIds.contains(routine)) (byWeek[week] ??= {}).add(routine);
  }
  return byWeek.values.where((s) => s.length == routineIds.length).length;
}
