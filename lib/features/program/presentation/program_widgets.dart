import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Prescribed last-set intensity technique; tap for the program's explanation.
class TechniqueChip extends ConsumerWidget {
  const TechniqueChip({super.key, required this.techniqueId});
  final String techniqueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final def = ref.watch(programProvider).value?.techniques[techniqueId];
    final label = def?.name ?? techniqueId;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.chip),
      onTap: def == null ? null : () => showTechniqueSheet(context, def.name, def.when, def.description),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.xp.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: AppColors.xp.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bolt_rounded, size: 16, color: AppColors.xp),
          const SizedBox(width: 4),
          Text('LAST SET: ${label.toUpperCase()}', style: AppType.label.copyWith(fontSize: 11, color: AppColors.xp, letterSpacing: 0.6)),
          const SizedBox(width: 4),
          const Icon(Icons.help_outline_rounded, size: 14, color: AppColors.xp),
        ]),
      ),
    );
  }
}

Future<void> showTechniqueSheet(BuildContext context, String name, String when, String description) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bolt_rounded, color: AppColors.xp),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: AppType.title)),
          ]),
          const SizedBox(height: 6),
          Text(when.toUpperCase(), style: AppType.label.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Text(description, style: AppType.body),
          const SizedBox(height: 12),
          Text('From the Min-Max Phase 2 program.', style: AppType.bodyS.copyWith(color: AppColors.textTertiary)),
        ]),
      ),
    ),
  );
}
