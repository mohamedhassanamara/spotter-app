import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../ranks/presentation/anatomy_graph.dart' show recoveryColor;
import '../domain/recovery.dart';

/// Lowercase muscle names with both chest heads shown as "chest".
String muscleNames(Iterable<Muscle> ms) {
  final set = ms.toSet();
  final out = <String>[];
  for (final m in Muscle.values) {
    if (!set.contains(m)) continue;
    if (m == Muscle.upperChest && set.contains(Muscle.lowerChest)) {
      out.add('chest');
      continue;
    }
    if (m == Muscle.lowerChest && set.contains(Muscle.upperChest)) continue;
    out.add(m.label.toLowerCase());
  }
  return out.join(', ');
}

/// Home: "Ready: chest, triceps, front delt · Recovering: quadriceps, glutes". Ready lists muscles
/// trained in the last two weeks that are back (listing all 20 fresh muscles would be noise).
class RecoveryCard extends ConsumerWidget {
  const RecoveryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(recoveryProvider);
    if (r == null) return const SizedBox.shrink();
    final trained = [for (final m in Muscle.values) if (r.of(m).lastHitAt != null) m];
    final ready = [for (final m in trained) if (r.of(m).band == RecoveryBand.ready) m];
    final recovering = r.inBand(RecoveryBand.recovering);
    final fatigued = r.inBand(RecoveryBand.fatigued);
    Widget line(RecoveryBand b, List<Muscle> ms) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${b.label}: ', style: TextStyle(color: recoveryColor(b), fontWeight: FontWeight.w800)),
              TextSpan(text: muscleNames(ms)),
            ]),
            key: ValueKey('recovery-${b.name}'),
            style: AppType.bodyS,
          ),
        );
    return GameCard(
      key: const ValueKey('recovery-card'),
      onTap: () => context.go('${Routes.progress}?tab=body&mode=recovery'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.healing_rounded, color: fatigued.isNotEmpty ? AppColors.red : (recovering.isNotEmpty ? AppColors.yellow : AppColors.green)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MUSCLE RECOVERY', style: AppType.label.copyWith(color: AppColors.textSecondary)),
            if (trained.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Everything is fresh: nothing trained in the last two weeks.', style: AppType.bodyS),
              ),
            if (ready.isNotEmpty) line(RecoveryBand.ready, ready),
            if (recovering.isNotEmpty) line(RecoveryBand.recovering, recovering),
            if (fatigued.isNotEmpty) line(RecoveryBand.fatigued, fatigued),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
      ]),
    );
  }
}
