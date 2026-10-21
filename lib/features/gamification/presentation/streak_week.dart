import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/dates.dart';
import '../../../core/motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/streaks.dart';

/// The current week (Monday → Sunday) on the after-workout Streak screen. Earlier days show their dumbbell or moon; today is
/// marked by an animated dumbbell stamp that lands when [stamp] runs from 0 to 1 (a haptic at the moment it lands).
/// Under the week, the same legend as the History calendar.
class StreakWeek extends StatefulWidget {
  const StreakWeek({super.key, required this.marks, required this.today, required this.stamp});

  final Map<DateTime, StreakDayMark> marks;
  final DateTime today;

  /// 0 → 1: the card has faded in (first third), then the stamp lands.
  final Animation<double> stamp;

  /// Where in [stamp] the stamp touches the calendar.
  static const double landsAt = 0.75;

  @override
  State<StreakWeek> createState() => _StreakWeekState();
}

class _StreakWeekState extends State<StreakWeek> {
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    widget.stamp.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.stamp.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!_landed && widget.stamp.value >= StreakWeek.landsAt) {
      _landed = true;
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final monday = weekStart(widget.today);
    final today = dateOnly(widget.today);
    final still = reduceMotion(context);
    return AnimatedBuilder(
      animation: widget.stamp,
      builder: (context, _) {
        final t = still ? 1.0 : widget.stamp.value;
        final appear = Curves.easeOut.transform((t / 0.3).clamp(0.0, 1.0));
        final drop = ((t - 0.3) / (StreakWeek.landsAt - 0.3)).clamp(0.0, 1.0); // the stamp falls in
        final settle = ((t - StreakWeek.landsAt) / (1 - StreakWeek.landsAt)).clamp(0.0, 1.0); // ring and little bounce after it lands
        return Opacity(
          opacity: appear,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - appear)),
            child: AppCard(
              key: const ValueKey('streak-week'),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  for (var i = 0; i < 7; i++) _day(addDays(monday, i), today, drop, settle),
                ]),
                const SizedBox(height: 10),
                const StreakLegend(),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _day(DateTime d, DateTime today, double drop, double settle) {
    const size = 34.0;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final isToday = d == today;
    final mark = widget.marks[d];
    Widget face;
    if (isToday) {
      // Hollow ring first; the stamp falls on it from 2.6× with a slight turn and lands with a bounce and an expanding ring.
      final scale = 1 + 1.6 * (1 - Curves.easeIn.transform(drop)) + 0.18 * (1 - Curves.easeOut.transform(settle)) * (drop >= 1 ? 1 : 0);
      final turn = -0.35 * (1 - Curves.easeIn.transform(drop));
      face = SizedBox(
        key: const ValueKey('streak-stamp'),
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primary, width: 2))),
          if (settle > 0 && settle < 1)
            Opacity(
              opacity: 1 - settle,
              child: Container(
                width: size * (1 + 0.9 * settle),
                height: size * (1 + 0.9 * settle),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primary, width: 2)),
              ),
            ),
          if (drop > 0)
            Opacity(
              opacity: drop.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: turn,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.5), blurRadius: 10)],
                    ),
                    child: const Icon(workoutDayIcon, size: 18, color: Color(0xFF06210F)),
                  ),
                ),
              ),
            ),
        ]),
      );
    } else if (d.isAfter(today)) {
      face = Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.outline)));
    } else if (mark == StreakDayMark.workout) {
      face = Container(
        key: ValueKey('streak-week-workout-${dayKey(d)}'),
        width: size,
        height: size,
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: const Icon(workoutDayIcon, size: 17, color: Color(0xFF06210F)),
      );
    } else if (mark == StreakDayMark.rest) {
      face = Container(
        key: ValueKey('streak-week-rest-${dayKey(d)}'),
        width: size,
        height: size,
        decoration: BoxDecoration(color: AppColors.surfaceTop, shape: BoxShape.circle, border: Border.all(color: restDayColor.withValues(alpha: 0.5))),
        child: const Icon(restDayIcon, size: 16, color: restDayColor),
      );
    } else {
      face = Container(width: size, height: size, decoration: const BoxDecoration(color: AppColors.surfaceTop, shape: BoxShape.circle));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(letters[d.weekday - 1], style: AppType.label.copyWith(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0)),
      const SizedBox(height: 4),
      face,
      const SizedBox(height: 4),
      Text('${d.day}', style: AppType.bodyS.copyWith(fontSize: 11, color: isToday ? AppColors.textPrimary : AppColors.textTertiary, fontFeatures: AppType.tabular)),
    ]);
  }
}
