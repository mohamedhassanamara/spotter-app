import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../router.dart';
import '../../gamification/domain/stats.dart';
import '../../ranks/presentation/rank_badge.dart';
import '../data/finish_service.dart';

/// Celebration after finishing a workout: XP counts up, then PRs, rank changes, discipline and
/// guardrail notes, with a staggered entrance.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(lastSummaryProvider);
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.check_circle_outline,
          title: 'Nothing to show',
          message: 'Finish a workout to see its summary.',
          action: FilledButton(onPressed: () => context.go(Routes.home), child: const Text('Home')),
        ),
      );
    }

    final sections = <Widget>[
      _Hero(s: s),
      _XpCard(s: s),
      _StatsRow(s: s),
      if (s.weeklyGoalReached)
        const GameCard(
          accent: AppColors.primary,
          glow: true,
          child: Row(children: [
            Icon(Icons.local_fire_department_rounded, color: AppColors.primary, size: 32),
            SizedBox(width: 12),
            Expanded(child: Text('Weekly goal complete! +100 XP', style: AppType.title)),
          ]),
        ),
      if (s.prs.isNotEmpty) _PrSection(prs: s.prs),
      if (s.rankChanges.any((r) => r.up) || s.rankDowns.isNotEmpty) _RankSection(s: s),
      if (s.flags.isNotEmpty || s.overrideSets > 0) _GuardrailSection(s: s),
      if (s.achievements.isNotEmpty || s.questsCompleted.isNotEmpty) _UnlocksSection(s: s),
      _HealthLine(saved: s.healthSaved),
    ];

    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: BigButton(label: 'Done', icon: Icons.check_rounded, onPressed: () => context.go(Routes.home)),
        ),
      ),
      body: Stack(
        children: [
          // Subtle radial glow behind the hero.
          Positioned(
            top: -120,
            left: -60,
            right: -60,
            child: IgnorePointer(
              child: Container(
                height: 420,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [AppColors.primary.withValues(alpha: 0.18), AppColors.background.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                for (var i = 0; i < sections.length; i++)
                  _Stagger(
                    index: i,
                    child: Padding(padding: const EdgeInsets.only(bottom: 12), child: sections[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fade + slide-up entrance, 70 ms apart (capped so the whole cascade stays under ~900 ms).
class _Stagger extends StatelessWidget {
  const _Stagger({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index * 70).clamp(0, 560);
    final total = delay + 320;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (context, v, child) {
        final t = Curves.easeOutCubic.transform(((v * total - delay) / 320).clamp(0.0, 1.0));
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child));
      },
      child: child,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.s});
  final SessionSummary s;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.verified_rounded, color: AppColors.primary, size: 44),
        const SizedBox(height: 8),
        Text('WORKOUT COMPLETE', textAlign: TextAlign.center, style: AppType.displayL.copyWith(letterSpacing: 1.5, fontSize: 30)),
        const SizedBox(height: 4),
        Text(s.name, textAlign: TextAlign.center, style: AppType.body.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _XpCard extends StatelessWidget {
  const _XpCard({required this.s});
  final SessionSummary s;

  @override
  Widget build(BuildContext context) {
    return GameCard(
      accent: AppColors.xp,
      glow: true,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CountUp(value: s.xpTotal, prefix: '+', suffix: ' XP', style: AppType.displayXL.copyWith(color: AppColors.xp)),
                const SizedBox(height: 4),
                Text(
                  [
                    '${s.xpSession} from sets and PRs',
                    if (s.xpBonus > 0) '${s.xpBonus} bonus',
                  ].join(' · '),
                  style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (s.levelAfter > s.levelBefore)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: const Interval(0.45, 1, curve: Curves.easeOutBack),
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.xp,
                  borderRadius: BorderRadius.circular(Radii.control),
                  boxShadow: [BoxShadow(color: AppColors.xp.withValues(alpha: 0.5), blurRadius: 14)],
                ),
                child: Text('LEVEL UP → ${s.levelAfter}',
                    style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w800, color: const Color(0xFF1B0B33))),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.s});
  final SessionSummary s;

  @override
  Widget build(BuildContext context) {
    final d = s.disciplinePct;
    final dColor = d == null
        ? AppColors.textSecondary
        : d >= 90
            ? AppColors.green
            : d >= 70
                ? AppColors.yellow
                : AppColors.red;
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: AppType.label.copyWith(fontSize: 10, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: AppType.number.copyWith(color: color ?? AppColors.textPrimary)),
              ),
            ],
          ),
        );
    return GameCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2 × 2 so large values (1h 04m, 12,640 kg) never collide on narrow phones.
          Row(children: [
            stat('Duration', formatDuration(s.duration)),
            stat('Volume', formatVolume(s.volume)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            stat('Working sets', '${s.workingSets}'),
            stat('Discipline', d == null ? '—' : '${d.round()}%', color: dColor),
          ]),
          const SizedBox(height: 8),
          Text('Discipline: % of sets within ±5% of the coach',
              style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

class _PrSection extends StatefulWidget {
  const _PrSection({required this.prs});
  final List<PrRecord> prs;

  @override
  State<_PrSection> createState() => _PrSectionState();
}

class _PrSectionState extends State<_PrSection> {
  @override
  void initState() {
    super.initState();
    // Two heavy taps when the PRs appear.
    Future<void>.delayed(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (mounted) await HapticFeedback.heavyImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC93C);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Personal records', padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
        for (final p in widget.prs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GameCard(
              accent: gold,
              glow: true,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: gold.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: const Icon(Icons.emoji_events_rounded, color: gold, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: AppType.title),
                    Text(
                      'e1RM ${p.e1rm.toStringAsFixed(1)} kg · was ${p.previous.toStringAsFixed(1)}',
                      style: AppType.bodyS.copyWith(color: AppColors.textSecondary, fontFeatures: AppType.tabular),
                    ),
                  ]),
                ),
                Text('+50 XP', style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w800, color: AppColors.xp)),
              ]),
            ),
          ),
      ],
    );
  }
}

class _RankSection extends StatelessWidget {
  const _RankSection({required this.s});
  final SessionSummary s;

  @override
  Widget build(BuildContext context) {
    final ups = s.rankChanges.where((r) => r.up).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ups.isNotEmpty) ...[
          const SectionLabel('Rank changes', padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
          GameCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(children: [
              for (final r in ups)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    RankBadge(score: r.toScore, size: BadgeSize.small, width: 44, animate: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name, style: AppType.title.copyWith(fontSize: 16)),
                        Text(r.from == null ? 'Placed: ${r.to}' : '${r.from} → ${r.to}',
                            style: AppType.bodyS.copyWith(color: tierColors[r.toScore.tier.index])),
                      ]),
                    ),
                    const Icon(Icons.trending_up_rounded, color: AppColors.primary),
                  ]),
                ),
            ]),
          ),
        ],
        // Rank-downs: one quiet line, no animation.
        if (s.rankDowns.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Text(
              'Slipped: ${s.rankDowns.map((r) => '${r.name} ${r.to}').join(', ')}. '
              'Ranks use your best e1RM of the last 90 days.',
              style: AppType.bodyS.copyWith(fontSize: 13, color: AppColors.textTertiary),
            ),
          ),
      ],
    );
  }
}

class _GuardrailSection extends StatelessWidget {
  const _GuardrailSection({required this.s});
  final SessionSummary s;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Guardrail', padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
        if (s.overrideSets > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GuardrailBanner(
              tone: GuardrailTone.override,
              title: '${s.overrideSets} override set${s.overrideSets == 1 ? '' : 's'} today',
              details: 'Override sets earn no XP. At RPE 9.5+ they don\'t count for ranks or PRs.',
            ),
          ),
        for (final f in s.flags)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GuardrailBanner(
              tone: GuardrailTone.egoFlag,
              title: '${f.exerciseName}: progression frozen',
              details: [
                f.message,
                if (f.freezeUntil != null) 'Frozen until ${DateFormat('EEE d MMM').format(f.freezeUntil!)}.',
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}

class _UnlocksSection extends StatelessWidget {
  const _UnlocksSection({required this.s});
  final SessionSummary s;

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, Color color, String title, String? subtitle, String? trailing) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GameCard(
            accent: color,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.title.copyWith(fontSize: 16)),
                  if (subtitle != null) Text(subtitle, style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
                ]),
              ),
              if (trailing != null)
                Text(trailing, style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w800, color: AppColors.xp)),
            ]),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.achievements.isNotEmpty) ...[
          const SectionLabel('Achievements unlocked', padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
          for (final a in s.achievements) tile(Icons.military_tech_rounded, AppColors.xp, a.title, a.description, null),
        ],
        if (s.questsCompleted.isNotEmpty) ...[
          const SectionLabel('Quests completed', padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
          for (final q in s.questsCompleted) tile(Icons.flag_rounded, AppColors.accent, q, null, '+40 XP'),
        ],
      ],
    );
  }
}

class _HealthLine extends StatelessWidget {
  const _HealthLine({required this.saved});
  final bool? saved;

  @override
  Widget build(BuildContext context) {
    final ok = saved == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(children: [
        Icon(ok ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: ok ? AppColors.danger : AppColors.textSecondary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ok
                ? 'Saved to Apple Health as Traditional Strength Training.'
                : 'Not saved to Apple Health (no write permission or Health unavailable).',
            style: AppType.bodyS.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ]),
    );
  }
}
