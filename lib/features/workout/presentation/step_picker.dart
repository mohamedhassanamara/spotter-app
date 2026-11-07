import 'package:flutter/material.dart';

import '../../../core/domain/weight_step.dart';
import '../../../core/theme/app_theme.dart';

/// What the step picker returned: a new [stepKg], or [reset] to the equipment default.
class StepChoice {
  const StepChoice.set(double this.stepKg) : reset = false;
  const StepChoice.reset()
      : stepKg = null,
        reset = true;
  final double? stepKg;
  final bool reset;
}

/// Long-press on the keypad's − / +: pick the weight step of this exercise (0.5 … 10, or a custom number).
/// Presets are kg; they are shown (and a custom number is typed) in [unit] and stored in kg.
Future<StepChoice?> showStepPicker(
  BuildContext context, {
  required String exerciseName,
  required double currentKg,
  required double defaultKg,
  WeightUnit unit = WeightUnit.kg,
}) =>
    showModalBottomSheet<StepChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _StepPickerBody(exerciseName: exerciseName, currentKg: currentKg, defaultKg: defaultKg, unit: unit),
    );

class _StepPickerBody extends StatefulWidget {
  const _StepPickerBody({required this.exerciseName, required this.currentKg, required this.defaultKg, required this.unit});
  final String exerciseName;
  final double currentKg, defaultKg;
  final WeightUnit unit;

  @override
  State<_StepPickerBody> createState() => _StepPickerBodyState();
}

class _StepPickerBodyState extends State<_StepPickerBody> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _submitCustom() {
    final v = double.tryParse(_custom.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    Navigator.of(context).pop(StepChoice.set(cleanWeight(widget.unit == WeightUnit.kg ? v : v / widget.unit.perKg)));
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.unit;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Weight step', style: AppType.title),
        const SizedBox(height: 4),
        Text('What − and + move ${widget.exerciseName} by (${u.label}).', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in stepPresets)
            ChoiceChip(
              key: ValueKey('step-preset-${formatNumber(p)}'),
              label: Text(formatNumber(toUnit(p, u))),
              selected: (p - widget.currentKg).abs() < 1e-6,
              onSelected: (_) => Navigator.of(context).pop(StepChoice.set(p)),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('step-custom'),
              controller: _custom,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(isDense: true, labelText: 'Custom (${u.label})'),
              onSubmitted: (_) => _submitCustom(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(key: const ValueKey('step-custom-set'), onPressed: _submitCustom, child: const Text('Set')),
        ]),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('step-reset'),
          onPressed: () => Navigator.of(context).pop(const StepChoice.reset()),
          child: Text('Reset to default (${formatNumber(toUnit(widget.defaultKg, u))} ${u.label})'),
        ),
      ]),
    );
  }
}
