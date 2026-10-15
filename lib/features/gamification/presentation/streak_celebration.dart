import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/game_ui.dart';

/// The flame and counter at Finish when this workout earned today's streak day: the number ticks
/// up from [from] to [to] with a pop and a haptic, in under 2 seconds.
class StreakCelebration extends StatefulWidget {
  const StreakCelebration({super.key, required this.from, required this.to});
  final int from;
  final int to;

  static const duration = Duration(milliseconds: 1500);

  @override
  State<StreakCelebration> createState() => _StreakCelebrationState();
}

class _StreakCelebrationState extends State<StreakCelebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: StreakCelebration.duration);
  bool _ticked = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_ticked && _c.value >= 0.45) {
        _ticked = true;
        HapticFeedback.mediumImpact();
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameCard(
      key: const ValueKey('streak-celebration'),
      accent: AppColors.warning,
      glow: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = _c.value;
          final shown = t < 0.45 ? widget.from : widget.to;
          // Pop when the number changes, settle after.
          final pop = t < 0.45 ? 1.0 : 1 + 0.35 * Curves.elasticOut.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0)).clamp(0.0, 1.0) * (1 - (t - 0.45) / 0.55);
          final flame = 1 + 0.25 * Curves.easeOutBack.transform((t / 0.45).clamp(0.0, 1.0)) * (t < 0.45 ? 1 : 0.6);
          return Row(children: [
            Transform.scale(scale: flame, child: const Icon(Icons.local_fire_department_rounded, color: AppColors.warning, size: 44)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Transform.scale(
                  scale: pop,
                  alignment: Alignment.centerLeft,
                  child: Text('$shown-day streak', key: const ValueKey('streak-celebration-count'), style: AppType.title.copyWith(color: AppColors.warning)),
                ),
                Text('Today counts: workout finished', style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
