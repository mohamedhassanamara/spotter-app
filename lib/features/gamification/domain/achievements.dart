import '../../../core/domain/training.dart';

/// Achievement metric types understood by [AchievementEvaluator]. Definitions live in
/// `assets/achievements.json`.
enum AchievementType {
  sessions,
  cleanSessionStreak,
  smartRestDays,
  comebacks,
  weeklyStreak,
  bestExerciseTier,
  discipline,
  prs,
  totalVolumeKg,
  level,
}

class AchievementDef {
  const AchievementDef({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
    required this.threshold,
  });

  final String key;
  final String title;
  final String description;
  final String icon;
  final AchievementType type;
  final double threshold;

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
    );
  }
}

/// Aggregated lifetime stats the achievements are checked against.
class AchievementStats {
  const AchievementStats({
    this.sessions = 0,
    this.longestCleanSessionStreak = 0,
    this.smartRestDays = 0,
    this.comebacks = 0,
    this.longestWeeklyStreak = 0,
    this.bestExerciseTierIndex = -1,
    this.disciplinePct30,
    this.workingSets30 = 0,
    this.prs = 0,
    this.totalVolumeKg = 0,
    this.level = 1,
  });

  final int sessions;
  final int longestCleanSessionStreak;
  final int smartRestDays;
  final int comebacks;
  final int longestWeeklyStreak;
  final int bestExerciseTierIndex;
  final double? disciplinePct30;
  final int workingSets30;
  final int prs;
  final double totalVolumeKg;
  final int level;

  /// Discipline only counts with enough sets to be meaningful.
  static const int minSetsForDiscipline = 50;

  double valueFor(AchievementType t) {
    switch (t) {
      case AchievementType.sessions:
        return sessions.toDouble();
      case AchievementType.cleanSessionStreak:
        return longestCleanSessionStreak.toDouble();
      case AchievementType.smartRestDays:
        return smartRestDays.toDouble();
      case AchievementType.comebacks:
        return comebacks.toDouble();
      case AchievementType.weeklyStreak:
        return longestWeeklyStreak.toDouble();
      case AchievementType.bestExerciseTier:
        return bestExerciseTierIndex.toDouble();
      case AchievementType.discipline:
        return workingSets30 >= minSetsForDiscipline ? (disciplinePct30 ?? 0) : 0;
      case AchievementType.prs:
        return prs.toDouble();
      case AchievementType.totalVolumeKg:
        return totalVolumeKg;
      case AchievementType.level:
        return level.toDouble();
    }
  }
}

class AchievementEvaluator {
  const AchievementEvaluator();

  bool isMet(AchievementDef def, AchievementStats stats) => stats.valueFor(def.type) >= def.threshold;

  /// 0..1 progress for display.
  double progress(AchievementDef def, AchievementStats stats) {
    if (def.threshold <= 0) return isMet(def, stats) ? 1 : 0;
    return (stats.valueFor(def.type) / def.threshold).clamp(0.0, 1.0);
  }

  List<AchievementDef> newlyUnlocked(List<AchievementDef> defs, AchievementStats stats, Set<String> alreadyUnlocked) =>
      [for (final d in defs) if (!alreadyUnlocked.contains(d.key) && isMet(d, stats)) d];
}

/// Longest run of consecutive finished sessions without any override set.
/// [sessionsOverrideFlags] is chronological: true when the session had an override.
int longestCleanStreak(List<bool> sessionsOverrideFlags) {
  var best = 0, run = 0;
  for (final hadOverride in sessionsOverrideFlags) {
    run = hadOverride ? 0 : run + 1;
    if (run > best) best = run;
  }
  return best;
}

/// Number of exercises where a deload session was later followed by a valid e1RM at least as
/// high as the best before the deload. [logsByExercise] are chronological per exercise.
int countComebacks(Iterable<List<ExerciseSessionLog>> logsByExercise) {
  var count = 0;
  for (final logs in logsByExercise) {
    var bestBefore = 0.0;
    double? target;
    for (final l in logs) {
      final e = l.bestE1rm(validOnly: true);
      if (target != null && e > 0 && e >= target - 1e-9) {
        count++;
        break;
      }
      if (l.suggestionKind.isDeload && bestBefore > 0) target ??= bestBefore;
      if (e > bestBefore) bestBefore = e;
    }
  }
  return count;
}
