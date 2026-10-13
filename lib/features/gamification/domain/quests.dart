import '../../../core/domain/muscles.dart';
import '../../../core/domain/training.dart';

enum QuestKey { topOfRange, trainGroup, followAll, logRpe, noOverride, sessions }

class QuestDef {
  const QuestDef({required this.key, required this.target, this.group});

  final QuestKey key;
  final int target;
  final BodyRegion? group;

  String get title {
    switch (key) {
      case QuestKey.topOfRange:
        return 'Hit the top of your rep range on $target lifts';
      case QuestKey.trainGroup:
        return 'Train ${group!.label.toLowerCase()} ${target == 2 ? 'twice' : '$target times'}';
      case QuestKey.followAll:
        return 'Follow every suggestion in $target sessions';
      case QuestKey.logRpe:
        return 'Log RPE on every working set in $target sessions';
      case QuestKey.noOverride:
        return 'Finish $target sessions without overriding the coach';
      case QuestKey.sessions:
        return 'Complete $target sessions this week';
    }
  }

  Map<String, Object?> toParams() => {'target': target, if (group != null) 'group': group!.name};

  static QuestDef fromParams(String key, Map<String, dynamic> params) {
    final k = QuestKey.values.firstWhere((e) => e.name == key);
    return QuestDef(
      key: k,
      target: (params['target'] as num).toInt(),
      group: params['group'] == null ? null : regionFromParam(params['group'] as String),
    );
  }
}

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
  const ExerciseActivity({required this.exerciseId, required this.primaryRegions, required this.repMax, required this.sets});
  final String exerciseId;
  final Set<BodyRegion> primaryRegions;
  final int repMax;
  final List<LoggedSet> sets;

  List<LoggedSet> get working => sets.where((s) => s.isWorking).toList();
}

class SessionActivity {
  const SessionActivity({required this.date, required this.exercises});
  final DateTime date;
  final List<ExerciseActivity> exercises;

  Iterable<LoggedSet> get workingSets => exercises.expand((e) => e.working);
}

class QuestGenInput {
  const QuestGenInput({
    required this.sessionsPerWeek,
    required this.groupSets4w,
    required this.disciplinePct,
    required this.rpeLoggedPct,
  });

  /// Average finished sessions per week over the last 4 weeks (sizes the no-override quest).
  final int sessionsPerWeek;

  /// Working sets per body region over the last 4 weeks (regions of primary muscles).
  final Map<BodyRegion, int> groupSets4w;
  final double? disciplinePct;
  final double? rpeLoggedPct;
}

class QuestEngine {
  const QuestEngine();

  /// Three quests, generated deterministically from the lifter's data each Monday.
  List<QuestDef> generate(QuestGenInput input) {
    final quests = <QuestDef>[const QuestDef(key: QuestKey.topOfRange, target: 2)];

    // Least-trained region the lifter trains (core is left to the lifter); defaults to back.
    const candidates = [BodyRegion.back, BodyRegion.chest, BodyRegion.shoulders, BodyRegion.legs, BodyRegion.arms];
    BodyRegion group = BodyRegion.back;
    if (input.groupSets4w.values.any((v) => v > 0)) {
      var min = 1 << 30;
      for (final g in candidates) {
        final v = input.groupSets4w[g] ?? 0;
        if (v < min) {
          min = v;
          group = g;
        }
      }
    }
    quests.add(QuestDef(key: QuestKey.trainGroup, target: 2, group: group));

    final discipline = input.disciplinePct;
    final rpe = input.rpeLoggedPct;
    if (discipline == null || discipline < 85) {
      quests.add(const QuestDef(key: QuestKey.followAll, target: 3));
    } else if (rpe == null || rpe < 90) {
      quests.add(const QuestDef(key: QuestKey.logRpe, target: 3));
    } else {
      quests.add(QuestDef(key: QuestKey.noOverride, target: (input.sessionsPerWeek - 1).clamp(2, 6)));
    }
    return quests;
  }

  /// Progress towards [quest] from the sessions of its week.
  int progress(QuestDef quest, List<SessionActivity> week) {
    switch (quest.key) {
      case QuestKey.topOfRange:
        final lifts = <String>{};
        for (final s in week) {
          for (final e in s.exercises) {
            final w = e.working;
            if (w.isNotEmpty && w.every((x) => x.reps >= e.repMax)) lifts.add(e.exerciseId);
          }
        }
        return lifts.length;
      case QuestKey.trainGroup:
        return week
            .where((s) => s.exercises.any((e) => e.primaryRegions.contains(quest.group) && e.working.isNotEmpty))
            .length;
      case QuestKey.followAll:
        return week.where((s) {
          final w = s.workingSets.where((x) => x.suggestedWeight != null).toList();
          return w.isNotEmpty && w.every((x) => x.followedSuggestion);
        }).length;
      case QuestKey.logRpe:
        return week.where((s) {
          final w = s.workingSets.toList();
          return w.isNotEmpty && w.every((x) => x.rpe != null);
        }).length;
      case QuestKey.noOverride:
        return week.where((s) => s.workingSets.isNotEmpty && !s.workingSets.any((x) => x.isOverride)).length;
      case QuestKey.sessions:
        return week.length;
    }
  }
}

/// Average finished sessions per week over the 4 weeks before [now] (at least 1).
int sessionsPerWeekLast4(Iterable<DateTime> sessionStarts, DateTime now) {
  final from = now.subtract(const Duration(days: 28));
  final n = sessionStarts.where((d) => d.isAfter(from) && !d.isAfter(now)).length;
  return (n / 4).round().clamp(1, 14);
}
