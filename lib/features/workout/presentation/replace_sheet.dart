import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../library/domain/exercise_info.dart';
import '../../library/domain/name_resolver.dart';
import '../../program/domain/program.dart';

/// The program's exercise and its listed substitutions, resolved to library exercises (null = not in the library).
List<(String, ExerciseInfo?)> programOptions(ProgramSlot? slot, Iterable<ExerciseInfo> catalog) {
  final resolver = ExerciseNameResolver(catalog);
  return [for (final o in <String>[if (slot != null) slot.exercise, ...?slot?.substitutions]) (o, resolver.resolve(o)?.exercise)];
}

/// "Replace exercise": the program's substitutions first, then a library search. Without substitutions it goes straight to the
/// search. Returns the chosen library exercise id, or null when cancelled.
Future<String?> pickReplacement(
  BuildContext context, {
  required String name,
  required String currentExerciseId,
  required ProgramSlot? slot,
  required List<(String, ExerciseInfo?)> options,
}) async {
  if (options.isEmpty) return context.push<String>(Routes.pickExercise);
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SheetBody(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      children: [
        Text('Replace $name', style: AppType.title),
        const SectionLabel('Program substitution'),
        for (final (label, info) in options)
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: info != null && info.id != currentExerciseId,
            leading: Icon(label == slot?.exercise ? Icons.star_rounded : Icons.swap_horiz_rounded, color: info == null ? AppColors.textTertiary : AppColors.primary),
            title: Text(label),
            subtitle: Text(info == null ? 'Not in the library — use search' : (info.id == currentExerciseId ? 'Current exercise' : info.name)),
            onTap: info == null ? null : () => Navigator.of(ctx).pop(info.id),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(ctx).pop('__search__'),
          icon: const Icon(Icons.search_rounded),
          label: const Text('Search the library'),
        ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return null;
  return picked == '__search__' ? context.push<String>(Routes.pickExercise) : picked;
}
