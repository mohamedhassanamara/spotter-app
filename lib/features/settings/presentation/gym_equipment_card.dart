import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/domain/gym.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../coach/domain/suggestion_engine.dart' show formatKg;

/// Settings → My gym equipment: the weights that exist. Every suggestion, warm-up and drop set
/// snaps to these (plus any weight you've logged on an exercise).
class GymEquipmentCard extends ConsumerWidget {
  const GymEquipmentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gymEquipmentProvider).value ?? GymEquipment.defaults;
    final repo = ref.read(gymRepositoryProvider);
    final catalog = ref.watch(catalogProvider).value ?? const {};
    const value = TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        ListTile(
          key: const ValueKey('gym-dumbbells'),
          title: const Text('Dumbbells'),
          subtitle: Text(GymEquipment.describeDumbbells(g.dumbbells)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final text = await promptText(context,
                title: 'Dumbbells (kg)', initial: _dumbbellText(g.dumbbells), hint: '2.5-50/2.5  or  2.5, 5, 7.5, 10');
            if (text == null) return;
            final parsed = GymEquipment.parseDumbbells(text);
            if (parsed == null) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use "from-to/step" or a list of weights')));
              return;
            }
            await repo.save(g.copyWith(dumbbells: parsed));
          },
        ),
        ListTile(
          key: const ValueKey('gym-plate'),
          title: const Text('Smallest barbell plate (each side)'),
          subtitle: Text('Barbell loads move in ${formatKg(g.barbellStep)} kg steps from the ${formatKg(g.barWeight)} kg bar'),
          trailing: Text('${formatKg(g.smallestPlate)} kg', style: value),
          onTap: () async {
            final v = await promptNumber(context, title: 'Smallest plate, each side', initial: g.smallestPlate, suffix: 'kg');
            if (v != null && v > 0 && v <= 25) await repo.save(g.copyWith(smallestPlate: v));
          },
        ),
        ListTile(
          key: const ValueKey('gym-stack'),
          title: const Text('Machines and cables'),
          subtitle: const Text('Default stack: first plate and step. Override per exercise from its menu.'),
          trailing: Text('${formatKg(g.stack.start)} + ${formatKg(g.stack.step)} kg', style: value),
          onTap: () async {
            final spec = await editStack(context, title: 'Default machine / cable stack', initial: g.stack);
            if (spec != null) await repo.save(g.copyWith(stack: spec));
          },
        ),
        for (final e in g.perExercise.entries)
          ListTile(
            key: ValueKey('gym-override-${e.key}'),
            dense: true,
            leading: const Icon(Icons.tune_rounded, size: 20),
            title: Text(catalog[e.key]?.name ?? e.key),
            subtitle: Text('Stack ${formatKg(e.value.start)} kg, then +${formatKg(e.value.step)} kg'),
            trailing: IconButton(
              tooltip: 'Back to the default stack',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => repo.setStack(e.key, null),
            ),
          ),
      ]),
    );
  }

  static String _dumbbellText(List<double> d) {
    if (d.length > 2) {
      final step = d[1] - d[0];
      final even = [for (var i = 1; i < d.length; i++) (d[i] - d[i - 1] - step).abs() < 0.01].every((x) => x);
      if (even) return '${formatKg(d.first)}-${formatKg(d.last)}/${formatKg(step)}';
    }
    return d.map(formatKg).join(', ');
  }
}

/// Two numbers: the stack's first plate and its step.
Future<StackSpec?> editStack(BuildContext context, {required String title, required StackSpec initial}) async {
  final start = TextEditingController(text: formatKg(initial.start));
  final step = TextEditingController(text: formatKg(initial.step));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const ValueKey('stack-start'),
          controller: start,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'First plate (kg)'),
        ),
        TextField(
          key: const ValueKey('stack-step'),
          controller: step,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Step (kg)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('stack-save'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
      ],
    ),
  );
  if (ok != true) return null;
  final a = double.tryParse(start.text.replaceAll(',', '.')), b = double.tryParse(step.text.replaceAll(',', '.'));
  if (a == null || b == null || a < 0 || b <= 0) return null;
  return StackSpec(start: a, step: b);
}
