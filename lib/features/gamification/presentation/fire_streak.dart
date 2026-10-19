import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion.dart';
import '../../../core/theme/app_theme.dart';

/// The streak at the end of a workout: a large flame drawn in code (no asset, no licence to carry) that flares up while the
/// number ticks from [from] to [to], with rising sparks and a haptic when the number changes. [onDone] fires when the show is over.
class FireStreak extends StatefulWidget {
  const FireStreak({super.key, required this.from, required this.to, this.onDone});
  final int from;
  final int to;
  final VoidCallback? onDone;

  static const duration = Duration(milliseconds: 2800);

  @override
  State<FireStreak> createState() => _FireStreakState();
}

class _FireStreakState extends State<FireStreak> with TickerProviderStateMixin {
  late final AnimationController _show = AnimationController(vsync: this, duration: FireStreak.duration);
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  bool _ticked = false;

  @override
  void initState() {
    super.initState();
    _show.addListener(() {
      if (!_ticked && _show.value >= 0.5) {
        _ticked = true;
        HapticFeedback.heavyImpact();
      }
    });
    _show.forward().whenComplete(() => widget.onDone?.call());
  }

  @override
  void dispose() {
    _show.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    if (still && !_show.isCompleted) _show.value = 1;
    return AnimatedBuilder(
      animation: Listenable.merge([_show, _loop]),
      builder: (context, _) {
        final t = _show.value;
        // 0 → 1 over the first half (ignite and flare), the number then ticks and the flame settles a little larger than it started.
        final flare = Curves.easeOutCubic.transform((t / 0.5).clamp(0.0, 1.0));
        final shown = t < 0.5 ? widget.from : widget.to;
        final pop = t < 0.5 ? 1.0 : 1 + 0.35 * (1 - ((t - 0.5) / 0.5).clamp(0.0, 1.0)) * Curves.elasticOut.transform(((t - 0.5) / 0.3).clamp(0.0, 1.0));
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            key: const ValueKey('streak-celebration'),
            height: 320,
            width: double.infinity,
            child: CustomPaint(painter: _FirePainter(time: still ? 0.3 : _loop.value + _show.value * 3, flare: flare)),
          ),
          Transform.scale(
            scale: pop,
            child: Text('$shown-day streak', key: const ValueKey('streak-celebration-count'), style: AppType.displayL.copyWith(color: AppColors.warning, fontSize: 34)),
          ),
          const SizedBox(height: 4),
          Text('Today counts: workout finished', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
        ]);
      },
    );
  }
}

class _FirePainter extends CustomPainter {
  _FirePainter({required this.time, required this.flare});
  final double time;
  final double flare;

  static const _sparks = 46;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, base = size.height * 0.88;
    final h = size.height * (0.38 + 0.5 * flare);
    final w = h * 0.62;

    // Glow on the ground.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, base), width: w * 2.2, height: h * 0.28),
      Paint()..shader = RadialGradient(colors: [const Color(0xFFFF7A18).withValues(alpha: 0.45 * flare), Colors.transparent]).createShader(Rect.fromCenter(center: Offset(cx, base), width: w * 2.2, height: h * 0.28)),
    );

    // Tongues: three flames behind, the main one in front; each layer smaller and hotter.
    void flame(double scale, double dx, double phase, List<Color> colors) {
      final fh = h * scale, fw = w * scale;
      final sway = math.sin(time * 2 * math.pi * 1.3 + phase) * fw * 0.10;
      final tip = Offset(cx + dx + sway * 1.8, base - fh);
      final wob = math.sin(time * 2 * math.pi * 2.1 + phase * 2) * fw * 0.05;
      final path = Path()
        ..moveTo(cx + dx, base)
        ..cubicTo(cx + dx - fw * 0.62 + wob, base - fh * 0.10, cx + dx - fw * 0.55 + sway, base - fh * 0.62, tip.dx, tip.dy)
        ..cubicTo(cx + dx + fw * 0.52 + sway, base - fh * 0.60, cx + dx + fw * 0.64 - wob, base - fh * 0.10, cx + dx, base)
        ..close();
      canvas.drawPath(
        path,
        Paint()..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: colors).createShader(Rect.fromLTWH(cx - fw, base - fh, fw * 2, fh)),
      );
    }

    flame(0.78, -w * 0.34, 1.7, const [Color(0xFFE03A0A), Color(0xFFFF8A1E)]);
    flame(0.72, w * 0.36, 3.1, const [Color(0xFFE03A0A), Color(0xFFFF9A2E)]);
    flame(1.0, 0, 0, const [Color(0xFFFF4D0D), Color(0xFFFF9D1F), Color(0xFFFFC93C)]);
    flame(0.66, 0, 2.2, const [Color(0xFFFFB02E), Color(0xFFFFE27A)]);
    flame(0.36, 0, 4.0, const [Color(0xFFFFF1B0), Color(0xFFFFFFFF)]);

    // Sparks rise from the base while the flame is up.
    final paint = Paint();
    for (var i = 0; i < _sparks; i++) {
      final r = math.Random(i * 7919);
      final speed = 0.55 + r.nextDouble() * 0.9;
      final phase = (time * speed + r.nextDouble()) % 1;
      final rise = h * (0.55 + r.nextDouble() * 0.9) * (0.4 + 0.6 * flare);
      final x = cx + (r.nextDouble() - 0.5) * w * 0.9 + math.sin(phase * 7 + i) * w * 0.12;
      final y = base - h * 0.15 - phase * rise;
      final a = (1 - phase) * flare * 0.95;
      paint.color = Color.lerp(const Color(0xFFFFE27A), const Color(0xFFFF5A1A), phase)!.withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), (1.2 + r.nextDouble() * 2.6) * (1 - phase * 0.6), paint);
    }
  }

  @override
  bool shouldRepaint(_FirePainter old) => old.time != time || old.flare != flare;
}
