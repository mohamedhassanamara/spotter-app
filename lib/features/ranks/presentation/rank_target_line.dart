import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../domain/rank_target.dart';
import '../domain/ranks.dart';

/// The prescribed reps (bottom of the range) and effort (reps in reserve) of an exercise outside a running workout:
/// the first routine that has it, else the exercise's default range at 2 in reserve.
final rankPrescriptionProvider = Provider.family<({int repMin, int rir}), String>((ref, exerciseId) {
  final routines = ref.watch(routinesProvider).value ?? const [];
  for (final r in routines) {
    for (final e in r.exercises) {
      if (e.exerciseId == exerciseId) return (repMin: e.repMin, rir: e.targetRir);
    }
  }
  return (repMin: ref.watch(catalogProvider).value?[exerciseId]?.defaultRange().min ?? 6, rir: 2);
});

/// "6 × 72.5 kg → Gold 2" for [exerciseId]: [repMin] reps at [rir] in reserve on the exercise's weight grid, reaching [targetE1rm].
/// Null when there is no next rank. [repMin]/[rir] default to the exercise's prescription.
String? rankTargetLineFor(
  WidgetRef ref, {
  required String exerciseId,
  required StrengthStandard standard,
  required double bodyweight,
  required double? targetE1rm,
  required String? nextLabel,
  int? repMin,
  int? rir,
}) {
  if (targetE1rm == null || nextLabel == null) return null;
  final grid = ref.watch(exerciseGridProvider(exerciseId));
  final rx = ref.watch(rankPrescriptionProvider(exerciseId));
  if (grid == null) return null;
  final set = rankTargetSet(
    standard: standard,
    bodyweight: bodyweight,
    targetE1rm: targetE1rm,
    repMin: repMin ?? rx.repMin,
    rir: rir ?? rx.rir,
    grid: grid,
  );
  return rankTargetLine(set, nextLabel);
}
