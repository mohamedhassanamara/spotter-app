import 'package:flutter/material.dart';

import '../../../core/db/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../coach/domain/guardrail.dart';
import '../../coach/domain/suggestion_engine.dart';

enum SetEditAction { complete, save, delete, uncomplete }

class SetEditResult {
  const SetEditResult({
    required this.action,
    required this.weight,
    required this.reps,
    required this.rpe,
    required this.isWarmup,
    this.reason,
  });

  final SetEditAction action;
  final double weight;
  final int reps;
  final double? rpe;
  final bool isWarmup;
  final OverrideReason? reason;
}

const List<double> rpeValues = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10];

String rirHint(double rpe) {
  final rir = 10 - rpe;
  if (rir <= 0) return 'Max effort, 0 reps left';
  final s = rir == rir.roundToDouble() ? rir.toStringAsFixed(0) : rir.toStringAsFixed(1);
  return '$s rep${rir == 1 ? '' : 's'} in reserve';
}

/// Bottom sheet for editing/completing a set one-handed.
Future<SetEditResult?> showSetEditor(
  BuildContext context, {
  required WorkoutSet set,
  required double increment,
  required String exerciseName,
  required int setNumber,
  required int targetRir,
}) {
  return showModalBottomSheet<SetEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SetEditor(
      set: set,
      increment: increment,
      exerciseName: exerciseName,
      setNumber: setNumber,
      targetRir: targetRir,
    ),
  );
}

class _SetEditor extends StatefulWidget {
  const _SetEditor({
    required this.set,
    required this.increment,
    required this.exerciseName,
    required this.setNumber,
    required this.targetRir,
  });

  final WorkoutSet set;
  final double increment;
  final String exerciseName;
  final int setNumber;
  final int targetRir;

  @override
  State<_SetEditor> createState() => _SetEditorState();
}

class _SetEditorState extends State<_SetEditor> {
  late double _weight = widget.set.weight;
  late int _reps = widget.set.reps;
  late double? _rpe = widget.set.rpe;
  late bool _warmup = widget.set.isWarmup;
  late OverrideReason? _reason = OverrideReason.fromName(widget.set.overrideReason);

  static const _guardrail = Guardrail();

  bool get _isOverride => _guardrail.isOverride(weight: _weight, suggested: widget.set.suggestedWeight, isWarmup: _warmup);

  bool get _canComplete => _reps > 0 && (!_isOverride || (_rpe != null && _reason != null));

  @override
  Widget build(BuildContext context) {
    final sug = widget.set.suggestedWeight;
    final pct = (sug != null && sug > 0) ? ((_weight - sug) / sug * 100) : null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.exerciseName, style: Theme.of(context).textTheme.titleLarge, maxLines: 2),
            const SizedBox(height: 4),
            Text(
              [
                _warmup ? 'Warm-up set' : 'Set ${widget.setNumber}',
                if (sug != null && !_warmup) 'coach: ${formatKg(sug)} kg × ${widget.set.suggestedReps ?? '–'}',
              ].join(' · '),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            StepperField(
              label: 'Weight',
              value: formatKg(_weight),
              unit: 'kg',
              onMinus: () => setState(() => _weight = (_weight - widget.increment).clamp(0, 1000).toDouble()),
              onPlus: () => setState(() => _weight = _weight + widget.increment),
              onTapValue: () async {
                final v = await promptNumber(context, title: 'Weight (kg)', initial: _weight, suffix: 'kg');
                if (v != null && v >= 0) setState(() => _weight = v);
              },
            ),
            const SizedBox(height: 16),
            StepperField(
              label: 'Reps',
              value: '$_reps',
              onMinus: () => setState(() => _reps = (_reps - 1).clamp(0, 100)),
              onPlus: () => setState(() => _reps = _reps + 1),
              onTapValue: () async {
                final v = await promptNumber(context, title: 'Reps', initial: _reps.toDouble(), decimal: false);
                if (v != null && v >= 0) setState(() => _reps = v.round());
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(_isOverride ? 'RPE (required)' : 'RPE',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: _isOverride && _rpe == null ? AppColors.warning : AppColors.textPrimary)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _rpe == null ? 'not logged (counts as RPE 9)' : rirHint(_rpe!),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in rpeValues)
                  ChoiceChip(
                    label: Text(formatRpe(v), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    selected: _rpe == v,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    selectedColor: v >= 9.5 ? AppColors.danger.withValues(alpha: 0.35) : AppColors.primary.withValues(alpha: 0.3),
                    onSelected: (_) => setState(() => _rpe = _rpe == v ? null : v),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Target: stop at ${widget.targetRir} reps in reserve (RPE ${10 - widget.targetRir}).',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Warm-up set', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Warm-ups never count for coaching, ranks or volume.'),
              value: _warmup,
              onChanged: (v) => setState(() => _warmup = v),
            ),
            if (_isOverride) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Override: ${pct!.toStringAsFixed(0)}% above the suggestion. Why the override?',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final r in OverrideReason.values)
                          ChoiceChip(
                            label: Text(r.label),
                            selected: _reason == r,
                            onSelected: (_) => setState(() => _reason = r),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Override sets earn no XP. At RPE 9.5+ they are excluded from ranks and PRs.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _canComplete ? () => _finish(SetEditAction.complete) : null,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.set.completed ? 'Update set' : 'Complete set'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _finish(widget.set.completed ? SetEditAction.uncomplete : SetEditAction.save),
                    child: Text(widget.set.completed ? 'Mark not done' : 'Save for later'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: () => _finish(SetEditAction.delete),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _finish(SetEditAction action) {
    Navigator.of(context).pop(SetEditResult(
      action: action,
      weight: _weight,
      reps: _reps,
      rpe: _rpe,
      isWarmup: _warmup,
      reason: _isOverride ? _reason : null,
    ));
  }
}
