import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../../core/db/database.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/equipment.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/muscles.dart';
import '../../library/domain/exercise_info.dart';
import '../../library/domain/load_kinds.dart';
import '../domain/ranks.dart';

/// Loads the editable strength standards and computes ranks from history.
class RanksRepository {
  static List<StrengthStandard>? _cache;

  static List<StrengthStandard> parseStandards(String json) {
    final raw = jsonDecode(json) as Map<String, dynamic>;
    final strict = (raw['machine_strictness'] as num? ?? 1).toDouble();
    final sc = raw['scaling'] as Map<String, dynamic>?;
    final scaling = sc == null
        ? BodyweightScaling.linear
        : BodyweightScaling(
            referenceBodyweight: (sc['reference_bodyweight'] as num).toDouble(),
            exponent: (sc['exponent'] as num).toDouble(),
          );
    return (raw['standards'] as List<dynamic>)
        .map((e) => StrengthStandard.fromJson(e as Map<String, dynamic>, machineStrictness: strict, scaling: scaling))
        .toList();
  }

  static Future<List<StrengthStandard>> loadStandards() async =>
      _cache ??= parseStandards(await rootBundle.loadString('assets/strength_standards.json'));

  /// Exercise ids whose e1RM includes bodyweight: bodyweight standards, "body only" equipment and assisted machines.
  static Set<String> bodyweightLoadedIds(List<StrengthStandard> standards, Map<String, ExerciseInfo> catalog) => {
        for (final s in standards)
          if (s.bodyweightLoaded) ...s.exerciseIds,
        for (final e in catalog.values)
          if (e.equipmentKind == EquipmentKind.bodyweight) e.id,
        ...extraBodyweightExerciseIds,
      };

  static BodyweightTimeline timeline(Iterable<BodyWeight> rows) => BodyweightTimeline([for (final r in rows) (r.measuredAt, r.kg)]);

  /// Ranks from valid working sets of the last 90 days, each scored at the bodyweight of its day.
  /// [myExerciseIds] (routines and history) are offered as hints for unranked muscles.
  static RankSummary compute({
    required TrainingHistory history,
    required List<StrengthStandard> standards,
    required Map<String, ExerciseInfo> catalog,
    required BodyweightTimeline bodyweights,
    required DateTime now,
    Set<String> excluded = const {},
    Set<String> myExerciseIds = const {},
  }) {
    if (bodyweights.isEmpty) return RankSummary.empty;
    final from = addDays(dateOnly(now), -RankCalculator.windowDays);
    final sets = <RankedSet>[
      for (final s in history.sessions)
        if (!s.startedAt.isBefore(from) && !s.startedAt.isAfter(now))
          for (final e in s.exercises)
            for (final set in e.workingSets)
              if (set.isValidForRecords)
                RankedSet(
                  exerciseId: e.exerciseId,
                  name: e.name,
                  weight: set.weight,
                  reps: set.reps,
                  rpe: set.rpe,
                  date: s.startedAt,
                  bodyweight: bodyweights.at(s.startedAt),
                ),
    ];
    final names = <String, String>{};
    for (final s in history.sessions) {
      for (final e in s.exercises) {
        names[e.exerciseId] = e.name;
      }
    }
    final mine = {...myExerciseIds, ...history.exerciseIds};
    return RankCalculator(standards).compute(
      sets: sets,
      targets: {for (final e in catalog.values) e.id: e.targets},
      currentBodyweight: bodyweights.latest,
      excluded: excluded,
      hintNames: {for (final id in mine) if (catalog[id] != null) id: names[id] ?? catalog[id]!.name},
    );
  }

  /// Best tier index over all ranked exercises (achievements), -1 when nothing is ranked.
  static int bestTierIndex(RankSummary s) => s.exercises.fold<int>(-1, (m, r) => r.score.tier.index > m ? r.score.tier.index : m);
}

/// Muscles of [targets] as display text, strongest first.
String musclesText(MuscleTargets targets) => targets.ranked.map((e) => e.key.label).join(', ');
