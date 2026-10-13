import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/training.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/guardrail.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../library/presentation/exercise_thumb.dart';
import '../../readiness/domain/readiness.dart';

/// One finished session, reloaded whenever history changes.
final sessionDetailProvider = FutureProvider.family<HistSession?, int>((ref, id) async {
  ref.watch(historyProvider);
  final catalog = await ref.watch(catalogProvider.future);
  return ref.watch(historyRepositoryProvider).loadSession(id, catalog);
});

/// Sets of a session whose saved numbers equal the suggestion, for sessions logged before the keypad-save
/// fix (empty for newer ones and for imports).
final suspectSetsProvider = FutureProvider.family<Set<int>, int>((ref, id) async {
  final s = await ref.watch(sessionDetailProvider(id).future);
  if (s == null || s.imported) return const {};
  final repo = ref.watch(historyRepositoryProvider);
  final fixedAt = await repo.savedValuesFixedAt();
  if (fixedAt == null || !s.startedAt.isBefore(fixedAt)) return const {};
  return repo.suspectSetIds(id);
});

String suggestionKindLabel(SuggestionKind k) => switch (k) {
      SuggestionKind.calibration => 'Calibration',
      SuggestionKind.seeded => 'Seeded from calibration',
      SuggestionKind.increase => 'Weight increase',
      SuggestionKind.addReps => 'Hold weight, add reps',
      SuggestionKind.reduce => 'Reduced (−5%)',
      SuggestionKind.plateauDeload => 'Plateau deload (−10%)',
      SuggestionKind.egoFreeze => 'Ego freeze (−5%)',
      SuggestionKind.none => 'No suggestion',
    };

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final int sessionId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete session?',
      message: 'Its sets, volume and session XP will be removed. Achievements already unlocked stay.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(historyRepositoryProvider).deleteSession(sessionId);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionDetailProvider(sessionId));
    final suspects = ref.watch(suspectSetsProvider(sessionId)).value ?? const <int>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          IconButton(
            tooltip: 'Delete session',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: AsyncBody<HistSession?>(
        value: session,
        builder: (s) {
          if (s == null) {
            return const EmptyState(icon: Icons.event_busy_rounded, title: 'Session not found', message: 'It may have been deleted.');
          }
          final band = ReadinessBand.fromName(s.readinessBand);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            children: [
              Text(s.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE d MMMM y · HH:mm').format(s.startedAt),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(children: [
                  Row(children: [
                    Expanded(child: StatTile(label: 'Duration', value: formatDuration(s.duration), icon: Icons.timer_outlined)),
                    Expanded(child: StatTile(label: 'Volume', value: formatVolume(s.volume), icon: Icons.stacked_bar_chart_rounded)),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: StatTile(label: 'XP', value: '+${s.xpEarned}', icon: Icons.bolt_rounded, color: AppColors.xp)),
                    Expanded(
                      child: StatTile(
                        label: 'Readiness',
                        value: s.readinessScore == null ? '—' : '${s.readinessScore}',
                        icon: Icons.favorite_rounded,
                        color: band == null ? null : bandColor(band),
                      ),
                    ),
                  ]),
                ]),
              ),
              if (suspects.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(
                  key: const ValueKey('suspect-sets-card'),
                  borderColor: AppColors.warning,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.fact_check_outlined, color: AppColors.warning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${suspects.length} set${suspects.length == 1 ? '' : 's'} below ${suspects.length == 1 ? 'is' : 'are'} exactly the suggestion. '
                        'Until a fix in this version, numbers typed on the keypad were sometimes replaced by the suggestion when you '
                        'tapped ✓. If you typed something else for ${suspects.length == 1 ? 'it' : 'any of them'}, tap the set to correct it.',
                        style: const TextStyle(height: 1.35),
                      ),
                    ),
                  ]),
                ),
              ],
              if (s.notes.trim().isNotEmpty) ...[
                const SectionHeader('Notes'),
                Text(s.notes, style: const TextStyle(fontSize: 15, height: 1.4)),
              ],
              const SectionHeader('Exercises'),
              if (s.exercises.isEmpty)
                const Text('No sets were logged.', style: TextStyle(color: AppColors.textSecondary)),
              for (final e in s.exercises) ...[
                _ExerciseBlock(exercise: e, suspects: suspects),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ExerciseBlock extends ConsumerWidget {
  const _ExerciseBlock({required this.exercise, this.suspects = const {}});
  final HistExercise exercise;
  final Set<int> suspects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = exercise;
    final info = ref.watch(catalogProvider).value?[e.exerciseId];
    var workingIndex = 0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => context.push(Routes.exerciseHistory(e.exerciseId)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              if (info != null) ...[ExerciseThumb(exercise: info, size: 40, radius: 10), const SizedBox(width: 12)],
              Expanded(child: Text(e.name, style: Theme.of(context).textTheme.titleMedium)),
              const Icon(Icons.show_chart_rounded, color: AppColors.textSecondary),
            ]),
          ),
        ),
        Text(
          '${suggestionKindLabel(e.suggestionKind)} · ${e.range} reps'
          '${e.suggestedWeight != null ? ' · suggested ${formatKg(e.suggestedWeight!)} kg' : ''}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        for (final hs in e.sets)
          _SetRow(set: hs, index: hs.set.isWarmup ? null : ++workingIndex, suspect: suspects.contains(hs.id)),
        if (e.notes.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(e.notes, style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
          ),
      ]),
    );
  }
}

class _SetRow extends ConsumerWidget {
  const _SetRow({required this.set, required this.index, this.suspect = false});
  final HistSet set;
  final int? index;

  /// The saved numbers are exactly the suggestion (see [suspectSetsProvider]).
  final bool suspect;

  Future<void> _correct(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(double, int)>(
      context: context,
      builder: (_) => _CorrectSetDialog(weight: set.set.weight, reps: set.set.reps),
    );
    if (result == null) return;
    await ref.read(historyRepositoryProvider).correctSet(set.id, weight: result.$1, reps: result.$2);
    ref.invalidate(historyProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = set.set;
    final reason = OverrideReason.fromName(set.overrideReason);
    return InkWell(
      key: ValueKey('hist-set-${set.id}'),
      onTap: s.completed ? () => _correct(context, ref) : null,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.isWarmup ? AppColors.surfaceHigh : AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            s.isWarmup ? 'W' : '$index',
            style: TextStyle(fontWeight: FontWeight.w800, color: s.isWarmup ? AppColors.textSecondary : AppColors.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${formatKg(s.weight)} kg × ${s.reps}${s.partials ? ' + partials' : ''}${s.rpe == null ? '' : ' @ RPE ${formatRpe(s.rpe!)}'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (suspect)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text('= the suggestion · tap to correct', style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            if (s.isOverride)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Override${reason == null ? '' : ': ${reason.label}'}'
                      '${s.isEgoSet ? ' · excluded from ranks' : ''}',
                      style: TextStyle(color: s.isEgoSet ? AppColors.danger : AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        if (!s.isWarmup)
          Text(
            'e1RM ${s.e1rm().toStringAsFixed(1)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
      ]),
    ));
  }
}

/// KG and REPS of a saved set. Owns its controllers so they outlive the closing animation.
class _CorrectSetDialog extends StatefulWidget {
  const _CorrectSetDialog({required this.weight, required this.reps});
  final double weight;
  final int reps;

  @override
  State<_CorrectSetDialog> createState() => _CorrectSetDialogState();
}

class _CorrectSetDialogState extends State<_CorrectSetDialog> {
  late final _kg = TextEditingController(text: formatKg(widget.weight));
  late final _reps = TextEditingController(text: '${widget.reps}');

  @override
  void dispose() {
    _kg.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _save() {
    final w = double.tryParse(_kg.text.replaceAll(',', '.')), r = int.tryParse(_reps.text);
    if (w == null || r == null || r < 0) return;
    Navigator.of(context).pop((w, r));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Correct this set'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const ValueKey('correct-kg'),
            controller: _kg,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'KG'),
          ),
          TextField(
            key: const ValueKey('correct-reps'),
            controller: _reps,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'REPS'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('correct-save'), onPressed: _save, child: const Text('Save')),
        ],
      );
}
