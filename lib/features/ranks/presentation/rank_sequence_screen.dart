import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../workout/data/finish_service.dart';
import '../domain/ranks.dart';
import 'rank_badge.dart';

/// The Finish rank sequence: the ranks in [gains] animate in turn, in the order given (rank-ups pop and buzz). Nothing
/// advances by itself: a tap fast-forwards the animation and, once it is done, a Continue button appears. [onDone] is
/// called once, by that button.
class RankSequenceScreen extends StatefulWidget {
  const RankSequenceScreen({super.key, required this.gains, required this.onDone, this.title = 'RANK PROGRESS'});

  final String title;

  /// [SessionSummary.rankGains]: lifts, muscles, regions, overall, in that order.
  final List<RankChange> gains;
  final VoidCallback onDone;

  /// Total time budget for the whole sequence; each row gets an equal share within [minRow]..[maxRow].
  static const budget = Duration(milliseconds: 6500);
  static const minRow = Duration(milliseconds: 380);
  static const maxRow = Duration(milliseconds: 1000);

  @override
  State<RankSequenceScreen> createState() => _RankSequenceScreenState();
}

class _Row {
  const _Row({this.header, this.change});
  final String? header;
  final RankChange? change;
}

class _RankSequenceScreenState extends State<RankSequenceScreen> with SingleTickerProviderStateMixin {
  late final List<_Row> _rows;
  late final Duration _rowTime;
  late final AnimationController _c;
  final _buzzedRows = <int>{};
  bool _done = false;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    String? last;
    _rows = [];
    for (final g in widget.gains) {
      final h = switch (g.scope) {
        RankChangeScope.exercise => 'LIFTS',
        RankChangeScope.muscle => 'MUSCLES',
        RankChangeScope.region => 'REGIONS',
        RankChangeScope.overall => 'OVERALL RANK',
      };
      if (h != last) {
        _rows.add(_Row(header: h));
        last = h;
      }
      _rows.add(_Row(change: g));
    }
    final changes = widget.gains.length;
    final ms = (RankSequenceScreen.budget.inMilliseconds / math.max(1, changes)).clamp(RankSequenceScreen.minRow.inMilliseconds, RankSequenceScreen.maxRow.inMilliseconds);
    _rowTime = Duration(milliseconds: ms.round());
    _c = AnimationController(vsync: this, duration: _rowTime * changes + const Duration(milliseconds: 700));
    _c.addListener(_haptics);
    if (changes == 0) {
      _complete = true;
    } else {
      _c.forward().whenComplete(() {
        if (mounted) setState(() => _complete = true);
      });
    }
  }

  /// Which gain (not header) a row is: its position among the changes.
  int _changeIndex(int row) => _rows.take(row + 1).where((r) => r.change != null).length - 1;

  /// Fraction of the whole timeline at which change [i] starts / ends.
  double _start(int i) => (_rowTime * i).inMilliseconds / _c.duration!.inMilliseconds;
  double _end(int i) => (_rowTime * (i + 1)).inMilliseconds / _c.duration!.inMilliseconds;

  void _haptics() {
    for (var r = 0; r < _rows.length; r++) {
      final ch = _rows[r].change;
      if (ch == null) continue;
      final i = _changeIndex(r);
      if (_c.value >= _end(i) - 0.002 && _buzzedRows.add(i)) {
        final labelChanged = ch.fromScore == null || ch.fromScore!.label != ch.toScore.label;
        if (labelChanged) {
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.selectionClick();
        }
      }
    }
  }

  /// A tap while it plays: jump to the end of the animation (the Continue button then shows).
  void _fastForward() {
    if (_complete) return;
    _c.value = 1;
    setState(() => _complete = true);
  }

  void _continue() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        key: const ValueKey('rank-sequence'),
        behavior: HitTestBehavior.opaque,
        onTap: _fastForward,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.title, textAlign: TextAlign.center, style: AppType.displayL.copyWith(letterSpacing: 4, fontSize: 24)),
              const SizedBox(height: 4),
              Text(_complete ? ' ' : 'Tap to skip the animation', textAlign: TextAlign.center, style: AppType.bodyS.copyWith(color: AppColors.textTertiary)),
              const SizedBox(height: 14),
              Expanded(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    // Top-aligned while it fits; once it overflows the newest rows stay in view (reverse scroll).
                    return SingleChildScrollView(
                      reverse: true,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (var r = 0; r < _rows.length; r++) _rowWidget(r),
                      ]),
                    );
                  },
                ),
              ),
              if (_complete) ...[
                if (widget.gains.isEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('No rank moved in this workout.', textAlign: TextAlign.center, style: AppType.body.copyWith(color: AppColors.textSecondary))),
                BigButton(key: const ValueKey('after-continue'), label: 'Continue', icon: Icons.arrow_forward_rounded, onPressed: _continue),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _rowWidget(int r) {
    final row = _rows[r];
    final v = _c.value;
    if (row.header != null) {
      // A header shows with the first change after it.
      final next = _changeIndex(r) + 1;
      if (v < _start(next)) return const SizedBox.shrink();
      return Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text(row.header!, style: AppType.label.copyWith(color: AppColors.textSecondary)));
    }
    final i = _changeIndex(r);
    if (v < _start(i)) return const SizedBox.shrink();
    final p = ((v - _start(i)) / (_end(i) - _start(i))).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _GainRow(key: ValueKey('gain-${row.change!.scope.name}-${row.change!.name}'), change: row.change!, progress: p),
    );
  }
}

/// One rank climbing from its old score to its new one: the badge follows the number, the RR bar fills (and wraps at a
/// division), and the badge pops when the division or tier changed.
class _GainRow extends StatelessWidget {
  const _GainRow({super.key, required this.change, required this.progress});
  final RankChange change;

  /// 0..1 through this row's animation.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final from = change.fromScore, to = change.toScore;
    final eased = Curves.easeOutCubic.transform(progress);
    // A first placement has no "from": the badge shows the new rank and only the bar fills.
    final shown = from == null ? to : RankScore(from.value + (to.value - from.value) * eased);
    final labelChanged = from == null || from.label != to.label;
    final pop = labelChanged && progress > 0.7 ? 1 + 0.28 * Curves.elasticOut.transform(((progress - 0.7) / 0.3).clamp(0.0, 1.0)).clamp(0.0, 1.0) * (1 - (progress - 0.7) / 0.3) : 1.0;
    final color = tierColor(shown.tier);
    final gainLp = ((to.value - (from?.value ?? 0)) * 100).round();
    final barProgress = from == null ? to.divisionProgress * eased : shown.divisionProgress;
    return Opacity(
      opacity: Curves.easeOut.transform((progress * 4).clamp(0.0, 1.0)),
      child: GameCard(
        accent: labelChanged && progress > 0.9 ? color : null,
        glow: labelChanged && progress > 0.9,
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(children: [
          Transform.scale(scale: pop, child: RankBadge(score: shown, size: BadgeSize.small, width: 44, animate: false)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(change.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.title.copyWith(fontSize: 16))),
                Text(from == null ? 'NEW' : '+$gainLp RR',
                    key: ValueKey('gain-lp-${change.name}'), style: AppType.bodyS.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
              ]),
              const SizedBox(height: 2),
              Text(
                from == null
                    ? 'Placed: ${to.labelWithRr}'
                    : (labelChanged && progress >= 0.99 ? '${from.label} → ${to.label}' : shown.labelWithRr),
                style: AppType.bodyS.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              RrBar(progress: barProgress, color: color, tier: shown.tier, height: 7),
            ]),
          ),
        ]),
      ),
    );
  }
}
