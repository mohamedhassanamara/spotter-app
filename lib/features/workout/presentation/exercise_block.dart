import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/domain/training.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../coach/domain/suggestion_engine.dart';
import '../../library/domain/exercise_info.dart';
import '../../library/domain/load_kinds.dart';
import '../../program/data/program_repository.dart';
import '../../ranks/presentation/rank_badge.dart';
import '../../library/presentation/exercise_thumb.dart';
import '../data/session_repository.dart';
import 'keypad.dart';

/// What the block needs from the screen for the keypad and supersets.
class BlockContext {
  const BlockContext({
    required this.focused,
    required this.buffer,
    required this.edited,
    required this.cellKey,
    required this.onFocus,
    required this.onComplete,
    required this.hideWarmups,
    required this.onToggleWarmups,
    required this.supersetLabel,
    required this.supersetColor,
    required this.onMenu,
  });

  final KeypadTarget? focused;
  final KeypadBuffer? buffer;
  final Set<KeypadTarget> edited;
  final GlobalKey Function(KeypadTarget) cellKey;
  final ValueChanged<KeypadTarget> onFocus;
  final Future<void> Function(WorkoutSet set) onComplete;
  final bool hideWarmups;
  final VoidCallback onToggleWarmups;

  /// "A1" etc. when in a superset.
  final String? supersetLabel;
  final Color? supersetColor;
  final Future<void> Function(String action) onMenu;
}

/// Previous session's sets of an exercise, matched by kind and order (warm-up i ↔ warm-up i,
/// working i ↔ working i, drop i ↔ drop i).
class PrevSets {
  PrevSets(List<LoggedSet> sets)
      : warmups = [for (final s in sets) if (s.isWarmup) s],
        working = [for (final s in sets) if (!s.isWarmup && !s.isDrop) s],
        drops = [for (final s in sets) if (s.isDrop) s];

  final List<LoggedSet> warmups;
  final List<LoggedSet> working;
  final List<LoggedSet> drops;

  static final empty = PrevSets(const []);

  LoggedSet? forSet(WorkoutSet s, List<WorkoutSet> all) {
    final list = s.isWarmup ? warmups : (s.setType == 'drop' ? drops : working);
    final same = [for (final x in all) if (x.isWarmup == s.isWarmup && (x.setType == 'drop') == (s.setType == 'drop')) x];
    final i = same.indexWhere((x) => x.id == s.id);
    return i >= 0 && i < list.length ? list[i] : null;
  }
}

String loadText(double kg) => kg == 0 ? 'BW' : formatKg(kg);

/// Short tags for the program's techniques.
String techniqueTag(String id) => switch (id) {
      'drop_sets_2x25' => 'DS',
      'myo_reps' => 'MYO',
      'weighted_static_hold_30s' => 'HOLD',
      'lengthened_partials' => 'LP',
      _ => id.substring(0, id.length.clamp(0, 4)).toUpperCase(),
    };

/// One exercise in the active workout: header, rest timer row, rank strip, prescription line and the
/// compact set table (SET | PREV | KG | REPS | EFFORT | ✓).
class ExerciseBlock extends ConsumerStatefulWidget {
  const ExerciseBlock({super.key, required this.exercise, required this.info, required this.ctx});

  final ActiveExercise exercise;
  final ExerciseInfo? info;
  final BlockContext ctx;

  @override
  ConsumerState<ExerciseBlock> createState() => _ExerciseBlockState();
}

class _ExerciseBlockState extends ConsumerState<ExerciseBlock> {
  bool _collapsed = false;
  bool _infoOpen = false;

  ActiveExercise get ex => widget.exercise;
  BlockContext get ctx => widget.ctx;

  @override
  Widget build(BuildContext context) {
    final name = ex.row.displayName ?? widget.info?.name ?? ex.row.exerciseId;
    final history = ref.watch(historyProvider).value;
    final prevLog = history?.sessions.reversed
        .expand((s) => s.exercises)
        .where((e) => e.exerciseId == ex.row.exerciseId)
        .firstOrNull;
    final prev = prevLog == null ? PrevSets.empty : PrevSets(prevLog.loggedSets);
    final warmups = ex.sets.where((s) => s.isWarmup).length;
    final visible = [for (final s in ex.sets) if (!(ctx.hideWarmups && s.isWarmup)) s];
    final firstRange = ex.sets.where((s) => !s.isWarmup && s.setType != 'drop').map(_rangeOf).firstOrNull;
    var number = 0;
    final numbers = <int, int>{};
    for (final s in ex.sets) {
      if (!s.isWarmup && s.setType != 'drop') numbers[s.id] = ++number;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(name),
        if (!_collapsed) ...[
          _restRow(),
          _RankStrip(exerciseId: ex.row.exerciseId),
          _prescription(),
          if (_infoOpen) _details(),
          const SizedBox(height: 4),
          const _TableHeader(),
          if (ctx.hideWarmups && warmups > 0)
            _MutedLine(text: '$warmups warm-up${warmups == 1 ? '' : 's'} hidden', onTap: ctx.onToggleWarmups),
          for (final s in visible)
            _SetRow(
              key: ValueKey('set-${s.id}'),
              set: s,
              number: numbers[s.id],
              higherRep: firstRange != null && !s.isWarmup && s.setType != 'drop' && _rangeOf(s) != firstRange ? _rangeOf(s) : null,
              prev: prev.forSet(s, ex.sets),
              exerciseRir: ex.row.targetRir,
              assisted: isAssisted(ex.row.exerciseId),
              ctx: ctx,
              onSetMenu: () => _setMenu(s),
            ),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                key: ValueKey('add-set-${ex.row.id}'),
                onPressed: () => ref.read(sessionRepositoryProvider).addSet(ex),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('ADD SET'),
              ),
            ),
            if (warmups > 0)
              TextButton(
                onPressed: ctx.onToggleWarmups,
                child: Text(ctx.hideWarmups ? 'Show warm-ups' : 'Hide warm-ups', style: const TextStyle(color: AppColors.textSecondary)),
              ),
          ]),
        ],
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Padding(padding: EdgeInsets.fromLTRB(ctx.supersetColor != null ? 14 : 10, 6, 6, 2), child: body),
        if (ctx.supersetColor != null)
          Positioned(left: 0, top: 0, bottom: 0, width: 5, child: ColoredBox(key: ValueKey('superset-bar-${ex.row.id}'), color: ctx.supersetColor!)),
      ]),
    );
  }

  static RepRange? _rangeOf(WorkoutSet s) =>
      s.targetRepMin == null || s.targetRepMax == null ? null : RepRange(s.targetRepMin!, s.targetRepMax!);

  Widget _header(String name) {
    return Row(children: [
      if (widget.info != null) ExerciseThumb(exercise: widget.info!, size: 40, radius: 10) else const SizedBox(width: 40, height: 40),
      const SizedBox(width: 10),
      if (ctx.supersetLabel != null)
        Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: ctx.supersetColor!.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
          child: Text(ctx.supersetLabel!, style: AppType.label.copyWith(color: ctx.supersetColor, letterSpacing: 0.5)),
        ),
      Expanded(
        child: InkWell(
          onTap: () => context.push(Routes.exercise(ex.row.exerciseId)),
          child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.title.copyWith(fontSize: 17, color: AppColors.accent)),
        ),
      ),
      IconButton(
        tooltip: _collapsed ? 'Expand' : 'Collapse',
        visualDensity: VisualDensity.compact,
        onPressed: () => setState(() => _collapsed = !_collapsed),
        icon: Icon(_collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded),
      ),
      PopupMenuButton<String>(
        key: ValueKey('menu-${ex.row.id}'),
        tooltip: 'Exercise menu',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: ctx.onMenu,
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'replace', child: Text('Replace')),
          PopupMenuItem(value: 'superset', child: Text(ex.row.supersetGroup == null ? 'Superset with…' : 'Remove from superset')),
          const PopupMenuItem(value: 'targets', child: Text('Target reps')),
          const PopupMenuItem(value: 'notes', child: Text('Notes')),
          const PopupMenuItem(value: 'howto', child: Text('How to')),
          const PopupMenuItem(value: 'up', child: Text('Move up')),
          const PopupMenuItem(value: 'down', child: Text('Move down')),
          const PopupMenuItem(value: 'reorder', child: Text('Reorder exercises')),
          const PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    ]);
  }

  Widget _restRow() {
    final on = ex.row.restEnabled;
    return Row(children: [
      const Icon(Icons.timer_outlined, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      InkWell(
        key: ValueKey('rest-edit-${ex.row.id}'),
        onTap: _editRest,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Rest Timer ${formatClock(Duration(seconds: ex.row.restSeconds))} ✎',
            style: AppType.bodyS.copyWith(color: on ? AppColors.textPrimary : AppColors.textTertiary),
          ),
        ),
      ),
      const Spacer(),
      Transform.scale(
        scale: 0.8,
        child: Switch(
          key: ValueKey('rest-switch-${ex.row.id}'),
          value: on,
          onChanged: (v) => ref.read(sessionRepositoryProvider).setRest(ex.row.id, enabled: v),
        ),
      ),
    ]);
  }

  Future<void> _editRest() async {
    const options = [30, 60, 90, 120, 150, 180, 240, 300];
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in options)
              ChoiceChip(
                label: Text(formatClock(Duration(seconds: o))),
                selected: o == ex.row.restSeconds,
                onSelected: (_) => Navigator.of(ctx).pop(o),
              ),
          ]),
        ),
      ),
    );
    if (picked != null) await ref.read(sessionRepositoryProvider).setRest(ex.row.id, seconds: picked);
  }

  /// "2×4–6 · 1×20 · last set to failure", with ⓘ for the program notes and the coach's why.
  Widget _prescription() {
    final sug = ex.suggestion;
    final working = [for (final s in ex.sets) if (!s.isWarmup && s.setType != 'drop') s];
    final parts = <String>[];
    RepRange? cur;
    var count = 0;
    void flush() {
      if (count > 0) parts.add('$count×${cur ?? ex.range}');
    }

    for (final s in working) {
      final r = _rangeOf(s) ?? ex.range;
      if (r != cur) {
        flush();
        cur = r;
        count = 0;
      }
      count++;
    }
    flush();
    final rirs = [for (final s in working) s.targetRir ?? ex.row.targetRir];
    String effort;
    if (rirs.isEmpty) {
      effort = '';
    } else if (rirs.every((r) => r == 0)) {
      effort = 'all sets to failure';
    } else if (rirs.last == 0) {
      effort = 'last set to failure';
    } else {
      effort = '${rirs.first} left in the tank';
    }
    final technique = working.map((s) => s.technique).whereType<String>().firstOrNull;
    final program = ref.watch(programProvider).value;
    final techName = technique == null ? null : (program?.techniques[technique]?.name ?? technique);
    final calibration = sug?.rampUp == true;
    final line = calibration
        ? 'Calibration: ramp up each set, stop 2 reps short'
        : [...parts, if (effort.isNotEmpty) effort, if (techName != null) 'last set: $techName'].join(' · ');
    return InkWell(
      key: ValueKey('prescription-${ex.row.id}'),
      onTap: () => setState(() => _infoOpen = !_infoOpen),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(line, style: AppType.bodyS.copyWith(color: calibration ? AppColors.accent : AppColors.textSecondary))),
          Icon(_infoOpen ? Icons.info_rounded : Icons.info_outline_rounded, size: 18, color: AppColors.textTertiary),
        ]),
      ),
    );
  }

  Widget _details() {
    final sug = ex.suggestion;
    final slots = decodeSlots(ex.row.programSlots);
    final program = ref.watch(programProvider).value;
    final slot = slots.isEmpty || program == null ? null : program.slot(slots.first);
    final freeze = ref.watch(activeFreezesProvider)[ex.row.exerciseId];
    final lines = <String>[
      if (sug != null) sug.headline,
      ...?sug?.why,
      if (slot != null && slot.notes.isNotEmpty) 'Program: ${slot.notes}',
      if (freeze != null) 'Progression frozen: ${freeze.reason}',
      if (ex.row.notes.isNotEmpty) 'Notes: ${ex.row.notes}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $l', style: AppType.bodyS.copyWith(fontSize: 13, color: AppColors.textSecondary)),
          ),
      ]),
    );
  }

  Future<void> _setMenu(WorkoutSet s) async {
    final techniques = ref.read(programProvider).value?.techniques ?? const {};
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(key: const ValueKey('kind-working'), title: const Text('Working set'), onTap: () => Navigator.of(ctx).pop('working')),
          ListTile(key: const ValueKey('kind-warmup'), leading: const Text('W'), title: const Text('Warm-up'), onTap: () => Navigator.of(ctx).pop('warmup')),
          ListTile(
            key: const ValueKey('kind-drop'),
            leading: const Text('D'),
            title: const Text('Drop set'),
            subtitle: const Text('Under the set above; counts for volume, not e1RM or ranks'),
            onTap: () => Navigator.of(ctx).pop('drop'),
          ),
          for (final t in techniques.values)
            ListTile(leading: Text(techniqueTag(t.id)), title: Text(t.name), onTap: () => Navigator.of(ctx).pop('technique:${t.id}')),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            title: const Text('Delete set', style: TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.of(ctx).pop('delete'),
          ),
        ]),
      ),
    );
    if (picked == null) return;
    final repo = ref.read(sessionRepositoryProvider);
    if (picked == 'delete') return repo.deleteSet(s);
    await repo.setSetKind(s, kind: picked);
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = AppType.label.copyWith(fontSize: 10, color: AppColors.textTertiary);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(children: [
        SizedBox(width: 40, child: Text('SET', style: style)),
        Expanded(flex: 4, child: Text('PREV', style: style)),
        Expanded(flex: 3, child: Center(child: Text('KG', style: style))),
        Expanded(flex: 3, child: Center(child: Text('REPS', style: style))),
        SizedBox(width: 46, child: Center(child: Text('EFFORT', style: style))),
        const SizedBox(width: 44),
      ]),
    );
  }
}

class _MutedLine extends StatelessWidget {
  const _MutedLine({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(text, style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textTertiary)),
        ),
      );
}

/// Badge, division, LP to the next division and the real kg gap. Never "???".
class _RankStrip extends ConsumerWidget {
  const _RankStrip({required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranks = ref.watch(ranksProvider).value;
    final hidden = (ref.watch(rankExclusionsProvider).value ?? const <String>{}).contains(exerciseId);
    final standards = ref.watch(standardsProvider).value ?? const [];
    final rank = ranks?.exercises.where((r) => r.exerciseId == exerciseId).firstOrNull;
    final hasStandard = standards.any((s) => s.exerciseIds.contains(exerciseId));
    final muted = AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textTertiary);
    Widget line(Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child);
    if (hidden) return line(Text('Hidden from ranks', style: muted));
    if (rank == null) {
      return line(Row(children: [
        const RankBadge(score: null, size: BadgeSize.small, width: 22, animate: false),
        const SizedBox(width: 8),
        Expanded(
          child: Text(hasStandard ? 'Unranked · complete a set to place it' : 'Not ranked (no strength standard)',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        ),
      ]));
    }
    final s = rank.score;
    final color = tierColor(s.tier);
    final gap = rank.nextThresholdKg == null ? null : (rank.nextThresholdKg! - rank.bestE1rm);
    return line(Row(children: [
      RankBadge(score: s, size: BadgeSize.small, width: 22, animate: false),
      const SizedBox(width: 8),
      Text(s.label, style: AppType.bodyS.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      const SizedBox(width: 8),
      Expanded(flex: 2, child: LpBar(progress: s.divisionProgress, color: color, height: 5)),
      const SizedBox(width: 8),
      Flexible(
        flex: 5,
        child: Text(
        gap == null ? 'top of the ladder' : '+${formatKg((gap.clamp(0, double.infinity) * 2).ceilToDouble() / 2)} kg e1RM to ${s.nextLabel}',
        key: ValueKey('rank-gap-$exerciseId'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: muted,
      ),
      ),
    ]));
  }
}

/// One compact set row.
class _SetRow extends ConsumerWidget {
  const _SetRow({
    super.key,
    required this.set,
    required this.number,
    required this.higherRep,
    required this.prev,
    required this.exerciseRir,
    required this.assisted,
    required this.ctx,
    required this.onSetMenu,
  });

  final WorkoutSet set;
  final int? number;
  final RepRange? higherRep;
  final LoggedSet? prev;
  final int exerciseRir;
  final bool assisted;
  final BlockContext ctx;
  final VoidCallback onSetMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = set;
    final drop = s.setType == 'drop';
    final repo = ref.read(sessionRepositoryProvider);
    final overridePct = !s.isWarmup && !drop && s.suggestedWeight != null && s.suggestedWeight! > 0 && repo.wouldOverride(s, s.weight)
        ? ((s.weight - s.suggestedWeight!) / s.suggestedWeight! * 100).round()
        : null;
    final effort = s.isWarmup ? null : (Effort.fromRpe(s.rpe) ?? Effort.fromRir(s.targetRir ?? exerciseRir));
    final label = s.isWarmup ? 'W' : (drop ? 'D' : '${number ?? ''}');
    final sub = s.technique != null ? techniqueTag(s.technique!) : (higherRep != null ? '×$higherRep' : null);
    final bg = s.completed ? AppColors.primary.withValues(alpha: 0.14) : Colors.transparent;

    Widget cell(KeypadField f) {
      final t = KeypadTarget(s.id, f);
      final focused = ctx.focused == t;
      final value = f == KeypadField.kg ? loadText(s.weight) : '${s.reps}';
      final entered = s.completed ||
          ctx.edited.contains(t) ||
          (f == KeypadField.kg ? (s.suggestedWeight != null && s.weight != s.suggestedWeight) : (s.suggestedReps != null && s.reps != s.suggestedReps));
      final buffer = focused ? ctx.buffer : null;
      final text = buffer != null && !buffer.isEmpty ? buffer.text : value;
      final grey = buffer == null || buffer.isEmpty ? !entered : false;
      final amber = f == KeypadField.kg && overridePct != null;
      return Expanded(
        flex: 3,
        child: GestureDetector(
          key: ctx.cellKey(t),
          behavior: HitTestBehavior.opaque,
          onTap: s.completed ? null : () => ctx.onFocus(t),
          child: Container(
            key: ValueKey('cell-${f.name}-${s.id}'),
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused ? AppColors.surfaceTop : AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: focused ? AppColors.accent : (amber ? AppColors.warning : Colors.transparent),
                width: focused ? 1.5 : 1,
              ),
            ),
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: AppType.body.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppType.tabular,
                  color: grey ? AppColors.textTertiary : AppColors.textPrimary,
                ),
              ),
              if (amber)
                Positioned(
                  right: -4,
                  top: -9,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(6)),
                    child: Text('+$overridePct%',
                        key: ValueKey('override-${s.id}'),
                        style: AppType.label.copyWith(fontSize: 9, color: const Color(0xFF2A1A00), letterSpacing: 0)),
                  ),
                ),
            ]),
          ),
        ),
      );
    }

    return Opacity(
      opacity: s.isWarmup && !s.completed ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: EdgeInsets.only(left: drop ? 14 : 0),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          InkWell(
            key: ValueKey('set-label-${s.id}'),
            onTap: s.completed ? null : onSetMenu,
            child: SizedBox(
              width: drop ? 26 : 40,
              height: 38,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label,
                    style: AppType.body.copyWith(
                      fontFamily: AppType.display,
                      fontWeight: FontWeight.w800,
                      color: s.isWarmup ? AppColors.warning : (drop ? AppColors.xp : AppColors.textPrimary),
                    )),
                if (sub != null) Text(sub, style: AppType.label.copyWith(fontSize: 9, color: AppColors.xp, letterSpacing: 0)),
              ]),
            ),
          ),
          Expanded(
            flex: 4,
            child: InkWell(
              key: ValueKey('prev-${s.id}'),
              onTap: prev == null || s.completed ? null : () => _copyPrev(ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  prev == null ? '—' : '${prev!.weight < 0 ? formatKg(prev!.weight) : loadText(prev!.weight)} × ${prev!.reps}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyS.copyWith(fontSize: 13, color: AppColors.textSecondary, fontFeatures: AppType.tabular),
                ),
              ),
            ),
          ),
          cell(KeypadField.kg),
          cell(KeypadField.reps),
          SizedBox(
            width: 46,
            child: Center(
              child: effort == null
                  ? const Text('—', style: TextStyle(color: AppColors.textTertiary))
                  : InkWell(
                      key: ValueKey('effort-${s.id}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: s.completed ? null : () => repo.updateSet(s.id, rpe: () => effort.next.rpe),
                      child: Container(
                        width: 36,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: effort == Effort.failure ? AppColors.danger.withValues(alpha: 0.16) : AppColors.surfaceTop,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(effort.label,
                            style: AppType.bodyS.copyWith(
                                fontFamily: AppType.display,
                                fontWeight: FontWeight.w800,
                                color: effort == Effort.failure ? AppColors.danger : AppColors.textPrimary)),
                      ),
                    ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 38,
            child: IconButton(
              tooltip: s.completed ? 'Mark not done' : 'Complete set',
              padding: EdgeInsets.zero,
              onPressed: () => ctx.onComplete(s),
              style: IconButton.styleFrom(
                backgroundColor: s.completed ? AppColors.primary : AppColors.surfaceTop,
                foregroundColor: s.completed ? const Color(0xFF06210F) : AppColors.textSecondary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.check_rounded, size: 22),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _copyPrev(WidgetRef ref) async {
    final p = prev!;
    await ref.read(sessionRepositoryProvider).updateSet(set.id, weight: p.weight, reps: p.reps);
    ctx.edited
      ..add(KeypadTarget(set.id, KeypadField.kg))
      ..add(KeypadTarget(set.id, KeypadField.reps));
  }
}
