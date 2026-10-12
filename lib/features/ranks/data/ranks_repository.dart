import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../../core/domain/dates.dart';
import '../../../core/domain/equipment.dart';
import '../../../core/domain/history.dart';
import '../../library/domain/exercise_info.dart';
import '../../library/domain/load_kinds.dart';
import '../domain/ranks.dart';

/// Loads the editable strength standards and computes ranks from history.
class RanksRepository {
  static List<StrengthStandard>? _cache;

  static Future<List<StrengthStandard>> loadStandards() async {
    if (_cache != null) return _cache!;
    final raw = jsonDecode(await rootBundle.loadString('assets/strength_standards.json')) as Map<String, dynamic>;
    return _cache = (raw['standards'] as List<dynamic>)
        .map((e) => StrengthStandard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Exercise ids whose e1RM includes bodyweight: bodyweight-loaded standards + "body only" equipment.
  static Set<String> bodyweightLoadedIds(List<StrengthStandard> standards, Map<String, ExerciseInfo> catalog) => {
        for (final s in standards)
          if (s.bodyweightLoaded) ...s.exerciseIds,
        for (final e in catalog.values)
          if (e.equipmentKind == EquipmentKind.bodyweight) e.id,
        ...extraBodyweightExerciseIds,
      };

  static RankSummary compute({
    required TrainingHistory history,
    required List<StrengthStandard> standards,
    required Set<String> bodyweightLoaded,
    required double bodyweight,
    required DateTime now,
    Set<String> excluded = const {},
  }) {
    final best = history.bestValidE1rm(
      from: addDays(dateOnly(now), -RankCalculator.windowDays),
      to: now,
      bodyweightLoaded: bodyweightLoaded,
      bodyweight: bodyweight,
    );
    best.removeWhere((id, _) => excluded.contains(id));
    return RankCalculator(standards).compute(bestE1rmByExercise: best, bodyweight: bodyweight);
  }
}
