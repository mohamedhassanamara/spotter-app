import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion.dart';
import '../../../core/theme/app_theme.dart';

/// Shown for a moment after Finish while the results are worked out: purely for anticipation (the work itself is fast).
class CalculatingResults extends StatefulWidget {
  const CalculatingResults({super.key});

  /// How long the loader plays at least.
  static const minimum = Duration(milliseconds: 1800);

  @override
  State<CalculatingResults> createState() => _CalculatingResultsState();
}

class _CalculatingResultsState extends State<CalculatingResults> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: CalculatingResults.minimum)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return Scaffold(
      key: const ValueKey('calculating-results'),
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final dots = '.' * (1 + (t * 9).floor() % 3);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _RingPainter(turn: still ? 0.25 : t * 3, progress: t),
                  child: Center(
                    child: Transform.scale(
                      scale: still ? 1 : 1 + 0.08 * math.sin(t * math.pi * 6),
                      child: const Icon(Icons.fitness_center_rounded, size: 44, color: AppColors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 260,
                child: Text('Calculating your results$dots', textAlign: TextAlign.left, style: AppType.title),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: Curves.easeInOut.transform(t), minHeight: 6, backgroundColor: AppColors.outline, color: AppColors.primary),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.turn, required this.progress});
  final double turn;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - 4, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = AppColors.outline);
    canvas.drawArc(
      rect.deflate(4),
      turn * 2 * math.pi - math.pi / 2,
      math.pi * (0.5 + 0.5 * math.sin(progress * math.pi)),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = AppColors.primary,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.turn != turn || old.progress != progress;
}
