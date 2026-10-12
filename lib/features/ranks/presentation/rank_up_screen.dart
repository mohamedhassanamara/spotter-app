import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../workout/data/finish_service.dart';
import '../domain/ranks.dart';
import 'rank_badge.dart';

/// Full-screen rank-up moment: the badge flies in, a glow bursts, the new rank name appears.
/// 2.6 s, tap anywhere to skip. Calls [onDone] once (on skip or at the end).
class RankUpScreen extends StatefulWidget {
  const RankUpScreen({super.key, required this.changes, required this.onDone, this.loop = false});

  /// Only rank-ups (see [RankChange.isRankUp]); the best one is the hero.
  final List<RankChange> changes;
  final VoidCallback onDone;

  /// Debug preview only: replay forever instead of finishing.
  final bool loop;

  static const duration = Duration(milliseconds: 2600);

  @override
  State<RankUpScreen> createState() => _RankUpScreenState();
}

class _RankUpScreenState extends State<RankUpScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: RankUpScreen.duration);
  bool _done = false;
  bool _buzzed = false;

  late final RankChange? _hero = widget.changes.isEmpty ? null : _pickHero(widget.changes);

  static RankChange _pickHero(List<RankChange> changes) {
    // Prefer the overall rank, then the highest new rank.
    final overall = changes.where((c) => c.scope == RankChangeScope.overall);
    if (overall.isNotEmpty) return overall.first;
    return changes.reduce((a, b) => b.toScore.value > a.toScore.value ? b : a);
  }

  @override
  void initState() {
    super.initState();
    if (_hero == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }
    _c.addListener(() {
      if (!_buzzed && _c.value >= 0.27) {
        _buzzed = true;
        HapticFeedback.heavyImpact();
      }
    });
    if (widget.loop) {
      _c.addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (!mounted) return;
            _buzzed = false;
            _c.forward(from: 0);
          });
        }
      });
      _c.forward();
    } else {
      _c.forward().whenComplete(_finish);
    }
  }

  void _finish() {
    if (_done) return;
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
    final hero = _hero;
    if (hero == null) return const Scaffold(backgroundColor: AppColors.background);
    final color = tierColors[hero.toScore.tier.index];
    final others = widget.changes.where((c) => c != hero).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            // Timeline (fraction of 2.6 s).
            final fly = Curves.easeOutBack.transform(((v - 0.0) / 0.3).clamp(0.0, 1.0));
            final burst = ((v - 0.25) / 0.35).clamp(0.0, 1.0);
            final title = Curves.easeOutCubic.transform(((v - 0.38) / 0.22).clamp(0.0, 1.0));
            final rest = Curves.easeOut.transform(((v - 0.55) / 0.25).clamp(0.0, 1.0));
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _BurstPainter(progress: burst, color: color)),
                SafeArea(
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      Opacity(
                        opacity: title,
                        child: Text(
                          'RANK UP',
                          style: TextStyle(
                            fontFamily: 'Oxanium',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Transform.translate(
                        offset: Offset(0, (1 - fly) * 420),
                        child: Transform.scale(
                          scale: 0.4 + 0.6 * fly,
                          child: RankBadge(score: hero.toScore, size: BadgeSize.hero),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Opacity(
                        opacity: title,
                        child: Transform.translate(
                          offset: Offset(0, (1 - title) * 24),
                          child: Column(
                            children: [
                              Text(
                                hero.toScore.label.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Oxanium',
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${hero.name}${hero.from == null ? '' : ' · from ${hero.from}'}',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Opacity(
                        opacity: rest,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 14,
                          runSpacing: 10,
                          children: [
                            for (final o in others.take(6))
                              Column(mainAxisSize: MainAxisSize.min, children: [
                                RankBadge(score: o.toScore, size: BadgeSize.small, width: 40, animate: false),
                                const SizedBox(height: 4),
                                Text(o.name, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ]),
                          ],
                        ),
                      ),
                      const Spacer(flex: 3),
                      Opacity(
                        opacity: rest,
                        child: const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text('Tap to continue', style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Expanding ring + light rays + sparks behind the badge.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final c = Offset(size.width / 2, size.height * 0.42);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final maxR = size.width * 0.9;
    canvas.drawCircle(
      c,
      maxR * 0.55,
      Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: 0.45 * (0.4 + 0.6 * fade)), color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: maxR * 0.55)),
    );
    canvas.drawCircle(
      c,
      40 + maxR * Curves.easeOutCubic.transform(progress),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * fade + 1
        ..color = color.withValues(alpha: 0.8 * fade),
    );
    final rnd = math.Random(7);
    final spark = Paint()..color = Colors.white.withValues(alpha: fade);
    for (var i = 0; i < 28; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = 60 + (maxR * 0.6) * Curves.easeOut.transform(progress) * (0.5 + rnd.nextDouble() * 0.5);
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * d, 1.5 + rnd.nextDouble() * 2.5 * fade, spark);
    }
    final ray = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.35 * fade);
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      final r0 = 90.0 + progress * 40, r1 = r0 + 60 * fade;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * r1, ray);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => old.progress != progress || old.color != color;
}

/// Demo data for the debug preview.
List<RankChange> demoRankUps() => [
      RankChange(
        name: 'Overall',
        fromScore: RankScore.of(Tier.gold, division: 1, lp: 80),
        toScore: RankScore.of(Tier.platinum, division: 4, lp: 5),
        scope: RankChangeScope.overall,
      ),
      RankChange(
        name: 'Bench press',
        fromScore: RankScore.of(Tier.diamond, division: 1, lp: 90),
        toScore: RankScore.of(Tier.master, lp: 12),
        scope: RankChangeScope.exercise,
      ),
      RankChange(
        name: 'Chest',
        fromScore: RankScore.of(Tier.emerald, division: 2, lp: 70),
        toScore: RankScore.of(Tier.emerald, division: 1, lp: 3),
        scope: RankChangeScope.group,
      ),
    ];
