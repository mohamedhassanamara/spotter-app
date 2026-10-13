import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/domain/gym.dart';
import '../../../core/domain/load_types.dart';
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
          title: const Text('Smallest plate'),
          subtitle: Text('One-sided plate machines (T-bar, pendulum) move in ${formatKg(g.smallestPlate)} kg steps; '
              'two-sided machines and barbells in ${formatKg(g.barbellStep)} kg (a pair)'),
          trailing: Text('${formatKg(g.smallestPlate)} kg', style: value),
          onTap: () async {
            final v = await promptNumber(context, title: 'Smallest plate', initial: g.smallestPlate, suffix: 'kg');
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
        for (final id in {...g.typeOverrides.keys, ...g.perExercise.keys})
          ListTile(
            key: ValueKey('gym-override-$id'),
            dense: true,
            leading: const Icon(Icons.tune_rounded, size: 20),
            title: Text(catalog[id]?.name ?? id),
            subtitle: Text(_overrideText(g, id)),
            trailing: IconButton(
              tooltip: 'Back to the default for this exercise',
              icon: const Icon(Icons.close_rounded),
              onPressed: () async {
                await repo.setStack(id, null);
                await repo.setLoadType(id, null);
              },
            ),
          ),
      ]),
    );
  }

  static String _overrideText(GymEquipment g, String id) {
    final type = g.typeOverrides[id];
    final stack = g.perExercise[id];
    return [
      if (type != null) '${type.label}${g.stepFor(id, type) == null ? '' : ', ${formatKg(g.stepFor(id, type)!)} kg steps'}',
      if (stack != null && (type == null || type == LoadType.stack)) 'Stack ${formatKg(stack.start)} kg, then +${formatKg(stack.step)} kg',
    ].join(' · ');
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

/// What the logger's "Weight steps…" returns: how the exercise is loaded and, for a stack, its numbers.
class LoadChoice {
  const LoadChoice({required this.type, this.stack, this.reset = false});
  final LoadType type;
  final StackSpec? stack;

  /// Go back to the classification and the gym's default stack.
  final bool reset;
}

/// Weight steps for one exercise: stack / plate-loaded one side / plate-loaded both sides, and the stack's
/// first plate and step.
Future<LoadChoice?> editLoad(
  BuildContext context, {
  required String title,
  required LoadType current,
  required StackSpec stack,
  required double plate,
}) =>
    showDialog<LoadChoice>(
      context: context,
      builder: (_) => _LoadDialog(title: title, current: current, stack: stack, plate: plate),
    );

class _LoadDialog extends StatefulWidget {
  const _LoadDialog({required this.title, required this.current, required this.stack, required this.plate});
  final String title;
  final LoadType current;
  final StackSpec stack;
  final double plate;

  @override
  State<_LoadDialog> createState() => _LoadDialogState();
}

class _LoadDialogState extends State<_LoadDialog> {
  late LoadType _type = LoadType.pickable.contains(widget.current) ? widget.current : LoadType.stack;
  late final _start = TextEditingController(text: formatKg(widget.stack.start));
  late final _step = TextEditingController(text: formatKg(widget.stack.step));

  @override
  void dispose() {
    _start.dispose();
    _step.dispose();
    super.dispose();
  }

  void _save() {
    StackSpec? spec;
    if (_type == LoadType.stack) {
      final a = double.tryParse(_start.text.replaceAll(',', '.')), b = double.tryParse(_step.text.replaceAll(',', '.'));
      if (a == null || b == null || a < 0 || b <= 0) return;
      spec = StackSpec(start: a, step: b);
    }
    Navigator.of(context).pop(LoadChoice(type: _type, stack: spec));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RadioGroup<LoadType>(
              groupValue: _type,
              onChanged: (v) => setState(() => _type = v ?? _type),
              child: Column(children: [
                for (final t in LoadType.pickable)
                  RadioListTile<LoadType>(
                    key: ValueKey('load-${t.name}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: t,
                    title: Text(t.label),
                    subtitle: Text(switch (t) {
                      LoadType.plateOneSide => 'One loading horn: ${formatKg(widget.plate)} kg steps (one plate)',
                      LoadType.plateBothSides => 'Plates on both sides: ${formatKg(widget.plate * 2)} kg steps (a pair)',
                      _ => 'Pin machine or cable: you set the first plate and the step',
                    }),
                  ),
              ]),
            ),
            if (_type == LoadType.stack) ...[
              TextField(
                key: const ValueKey('stack-start'),
                controller: _start,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'First plate (kg)'),
              ),
              TextField(
                key: const ValueKey('stack-step'),
                controller: _step,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Step (kg)'),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(
            key: const ValueKey('load-reset'),
            onPressed: () => Navigator.of(context).pop(LoadChoice(type: widget.current, reset: true)),
            child: const Text('Use default'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('stack-save'), onPressed: _save, child: const Text('Save')),
        ],
      );
}

/// Two numbers: the stack's first plate and its step (the gym-wide default stack in Settings).
Future<StackSpec?> editStack(BuildContext context, {required String title, required StackSpec initial}) async {
  final start = TextEditingController(text: formatKg(initial.start));
  final step = TextEditingController(text: formatKg(initial.step));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: start,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'First plate (kg)'),
        ),
        TextField(
          controller: step,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Step (kg)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
      ],
    ),
  );
  final a = double.tryParse(start.text.replaceAll(',', '.')), b = double.tryParse(step.text.replaceAll(',', '.'));
  if (ok != true || a == null || b == null || a < 0 || b <= 0) return null;
  return StackSpec(start: a, step: b);
}
