import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
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

/// "Lift ⇄ Bodyweight" on a rank-up target. One setting for every target (strip, exercise page, muscle sheet).
class RankTargetModeToggle extends ConsumerWidget {
  const RankTargetModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(rankTargetModeProvider);
    Widget seg(RankTargetMode m, String label) {
      final on = mode == m;
      return InkWell(
        key: ValueKey('rank-target-mode-${m.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => ref.read(rankTargetModeProvider.notifier).set(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: on ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: on ? AppColors.primary : AppColors.textTertiary)),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [seg(RankTargetMode.lift, 'Lift'), seg(RankTargetMode.bodyweight, 'Bodyweight')]);
  }
}

/// A bodyweight projection line: "What if · your 6 × 70 kg at **101 kg** bodyweight → Gold 2". The tag marks it as a
/// projection; the bodyweight is bold.
Widget whatIfText(String line, {TextStyle? style, int? maxLines, TextAlign? textAlign, Key? key}) {
  final m = RegExp(r'(\d+(?:\.\d+)? kg) (bodyweight)').firstMatch(line);
  final base = style ?? const TextStyle();
  return Text.rich(
    TextSpan(children: [
      TextSpan(text: 'What if · ', style: const TextStyle(fontStyle: FontStyle.italic)),
      if (m == null)
        TextSpan(text: line)
      else ...[
        TextSpan(text: line.substring(0, m.start)),
        TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: line.substring(m.start + m.group(1)!.length)),
      ],
    ]),
    key: key,
    style: base,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    textAlign: textAlign,
  );
}
