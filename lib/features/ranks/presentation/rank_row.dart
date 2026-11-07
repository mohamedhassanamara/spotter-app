import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../coach/domain/suggestion_engine.dart' show formatKg;
import '../domain/exercise_rank_state.dart';
import '../domain/rank_row_text.dart';
import '../domain/rank_target.dart';
import '../domain/ranks.dart';
import 'progress_screen.dart' show enterBodyweight;
import 'rank_badge.dart';

/// Width of the [Lift | BW] control, the same in every state so line 1 never shifts.
const double rankModeToggleWidth = 88;

/// Height of line 1 (badge, rank, bar, toggle).
const double rankRowLineOneHeight = 26;

/// The largest text scale the rank row grows to: past it the row keeps its size (its text shrinks and cuts instead), so the card height is stable.
const double rankRowMaxTextScale = 1.3;

/// Compact segmented control: [Lift | BW]. Fixed width, right-aligned by its parent. One global mode for every rank target.
class RankModeSegmented extends ConsumerWidget {
  const RankModeSegmented({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(rankTargetModeProvider);
    Widget seg(RankTargetMode m, String label, String key) {
      final on = mode == m;
      return Expanded(
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(7),
          onTap: () => ref.read(rankTargetModeProvider.notifier).set(m),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.primary.withValues(alpha: 0.20) : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: on ? AppColors.primary : AppColors.textTertiary)),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('rank-mode-toggle'),
      width: rankModeToggleWidth,
      height: 24,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        seg(RankTargetMode.lift, 'Lift', 'rank-target-mode-lift'),
        seg(RankTargetMode.bodyweight, 'BW', 'rank-target-mode-bodyweight'),
      ]),
    );
  }
}

/// The rank row of an exercise card, two lines of fixed height:
///  1. badge, rank name, progress bar (flexible), [Lift | BW];
///  2. one line of target text over the full width (shrinks, then ellipsis); tap it or ⓘ for the full text.
/// Everything comes from `exerciseRankStateProvider(exerciseId)`: a never-done or just-added exercise shows "Unranked" and its
/// Bronze 1 target at once. When a set raises the rank the bar fills and the badge pops (with a haptic).
class RankRow extends ConsumerStatefulWidget {
  const RankRow({super.key, required this.exerciseId, required this.repMin, required this.rir});
  final String exerciseId;

  /// The prescription the target is quoted at: bottom of the rep range, prescribed reps in reserve.
  final int repMin;
  final int rir;

  @override
  ConsumerState<RankRow> createState() => _RankRowState();
}

class _RankRowState extends ConsumerState<RankRow> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  RankScore? _from, _to;
  bool _labelChanged = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _follow(RankScore? live) {
    if (live == null) {
      _to = null;
      _from = null;
      return;
    }
    final to = _to;
    if (to == null || (live.value - to.value).abs() < 0.0005) {
      _to ??= live;
      return;
    }
    final shown = _shownScore(live);
    if (live.value > to.value) {
      _from = shown;
      _to = live;
      _labelChanged = shown.label != live.label;
      _c.forward(from: 0);
      _labelChanged ? HapticFeedback.heavyImpact() : HapticFeedback.selectionClick();
    } else {
      // A set was un-ticked: back down without ceremony.
      _from = null;
      _to = live;
      _labelChanged = false;
      _c.value = 1;
    }
  }

  RankScore _shownScore(RankScore fallback) {
    final to = _to, from = _from;
    if (to == null) return fallback;
    if (from == null || !_c.isAnimating) return to;
    return RankScore(from.value + (to.value - from.value) * Curves.easeOutCubic.transform(_c.value));
  }

  /// The target text for the current state and mode, plus the set behind it.
  ({RankRowText text, RankTargetSet? set}) _text(ExerciseRankState st, RankScore? shown, bool bodyweightMode) {
    final std = st.standard ?? st.baseline?.standard;
    final grid = ref.watch(exerciseGridProvider(st.exerciseId));
    final next = st.nextE1rm;
    RankTargetSet? set;
    if (std != null && grid != null && next != null) {
      set = rankTargetSet(standard: std, bodyweight: st.bodyweight, targetE1rm: next, repMin: widget.repMin, rir: widget.rir, grid: grid);
    }
    return (
      text: buildRankRowText(
        hidden: st.hidden,
        bodyweightMode: bodyweightMode,
        bodyweight: st.bodyweight,
        score: shown,
        standard: std,
        nextLabel: shown == null ? st.nextLabel : shown.nextLabel,
        set: set,
        setKnown: grid != null,
      ),
      set: set,
    );
  }

  Future<void> _openDetail(ExerciseRankState st, RankScore? shown, RankRowText text, bool bodyweightMode) async {
    if (text.needsBodyweight) return enterBodyweight(context, ref);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _RankDetailSheet(state: st, score: shown, text: text, bodyweightMode: bodyweightMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(exerciseRankStateProvider(widget.exerciseId));
    final bodyweightMode = ref.watch(rankTargetModeProvider) == RankTargetMode.bodyweight;
    final live = st.hidden ? null : st.score;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _follow(live);
    });
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: rankRowMaxTextScale);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final s = live == null ? null : (_to == null ? live : _shownScore(live));
          final color = s == null ? AppColors.textTertiary : tierColor(s.tier);
          final t = _c.isAnimating ? _c.value : 1.0;
          final pop = _labelChanged && _c.isAnimating && t > 0.6
              ? 1 + 0.45 * Curves.elasticOut.transform(((t - 0.6) / 0.4).clamp(0.0, 1.0)).clamp(0.0, 1.0) * (1 - (t - 0.6) / 0.4)
              : 1.0;
          final r = _text(st, s, bodyweightMode);
          final muted = AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textTertiary);
          final id = widget.exerciseId;
          final label = st.hidden ? 'Off' : (s?.label ?? 'Unranked');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: rankRowLineOneHeight,
                child: LayoutBuilder(builder: (context, c) {
                  // Badge 22 + three gaps of 8 + the control; the bar keeps at least 24 and the rank name takes what is left (then cuts).
                  final labelMax = (c.maxWidth - 22 - 24 - rankModeToggleWidth - 24).clamp(0.0, double.infinity);
                  return Row(children: [
                    Transform.scale(scale: pop, child: RankBadge(key: ValueKey('rank-strip-badge-$id'), score: s, size: BadgeSize.small, width: 22, animate: false)),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: labelMax),
                      child: Text(label,
                          key: ValueKey('rank-strip-label-$id'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: AppType.bodyS.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: RrBar(key: ValueKey('rank-strip-lp-$id'), progress: s?.divisionProgress ?? 0, color: color, tier: s?.tier ?? Tier.iron, height: 5)),
                    const SizedBox(width: 8),
                    Opacity(opacity: st.hidden ? 0 : 1, child: IgnorePointer(ignoring: st.hidden, child: const RankModeSegmented())),
                  ]);
                }),
              ),
              InkWell(
                key: ValueKey('rank-row-line2-$id'),
                onTap: () => _openDetail(st, s, r.text, bodyweightMode),
                child: Row(children: [
                  Expanded(child: OneLineFit(r.text.line, key: ValueKey('rank-gap-$id'), style: muted, minScale: 0.8)),
                  const SizedBox(width: 6),
                  Icon(Icons.info_outline_rounded, key: ValueKey('rank-info-$id'), size: 15, color: AppColors.textTertiary),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// The full text of the rank row: current rank, the target in both modes, the estimate flag and the bodyweight note.
class _RankDetailSheet extends ConsumerWidget {
  const _RankDetailSheet({required this.state, required this.score, required this.text, required this.bodyweightMode});
  final ExerciseRankState state;
  final RankScore? score;
  final RankRowText text;
  final bool bodyweightMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = AppType.bodyS.copyWith(color: AppColors.textSecondary);
    final std = state.standard;
    final ratio = relativeStrength(score: score, standard: std, bodyweight: state.bodyweight);
    return SheetBody(
      key: const ValueKey('rank-detail-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      children: [
        Text(score?.labelWithRr ?? 'Unranked', style: AppType.title),
        const SizedBox(height: 4),
        Text(bodyweightMode ? 'Bodyweight mode' : 'Lift mode', style: body),
        const SizedBox(height: 12),
        Text(text.line.isEmpty ? '—' : text.line, key: const ValueKey('rank-detail-text'), style: AppType.bodyS.copyWith(fontSize: 16, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        if (ratio != null) Text('Relative strength now: ${ratioText(ratio)} (best set e1RM ÷ bodyweight${state.bodyweight > 0 ? ', ${formatKg(state.bodyweight)} kg' : ''}).', style: body),
        if (state.estimated) ...[
          const SizedBox(height: 8),
          Text('Estimated standard: this exercise has no hand-made strength table, so its levels come from its movement pattern and equipment.',
              key: const ValueKey('rank-detail-estimated'), style: body),
        ],
        const SizedBox(height: 8),
        Text(bodyweightModeNote, key: const ValueKey('rank-detail-note'), style: body),
      ],
    );
  }
}
