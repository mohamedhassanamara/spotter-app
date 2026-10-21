import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import 'package:flutter/services.dart';

import '../../features/ranks/domain/ranks.dart' show Tier;
import '../theme/app_theme.dart';

/// Layered surface: subtle gradient, 1 px border, optional accent border + glow. See docs/DESIGN.md.
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.child,
    this.onTap,
    this.accent,
    this.padding = const EdgeInsets.all(18),
    this.glow = false,
    this.fill,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? accent;
  final EdgeInsets padding;
  final bool glow;

  /// Overrides the gradient with a tinted fill.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final a = accent;
    final radius = BorderRadius.circular(Radii.card);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (a != null && glow) BoxShadow(color: a.withValues(alpha: 0.18), blurRadius: 24, spreadRadius: -2),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: fill,
            gradient: fill != null
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(AppColors.surface, a ?? AppColors.surfaceHigh, a == null ? 0.35 : 0.07)!,
                      AppColors.surface,
                      Color.lerp(AppColors.surface, Colors.black, 0.18)!,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
            border: Border.all(color: a == null ? AppColors.outline : a.withValues(alpha: 0.45), width: a == null ? 1 : 1.4),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Uppercase section label with an optional trailing widget.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 22, 4, 10)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: AppType.label.copyWith(color: AppColors.textSecondary))),
        ?trailing,
      ]),
    );
  }
}

/// Tier-coloured progress bar with an optional RR readout.
class RrBar extends StatelessWidget {
  const RrBar({super.key, required this.progress, required this.color, this.tier, this.rr, this.height = 10, this.trailing});
  final double progress;
  final Color color;

  /// When set, the fill is this tier's two-colour gradient (deeper → lighter).
  final Tier? tier;
  final int? rr;
  final double height;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(children: [
        Container(height: height, color: AppColors.surfaceTop),
        FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: tier == null
                  ? LinearGradient(colors: [Color.lerp(color, Colors.black, 0.25)!, color])
                  : LinearGradient(colors: [tierGradients[tier!.index].$2, tierGradients[tier!.index].$1]),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8)],
            ),
          ),
        ),
      ]),
    );
    if (rr == null && trailing == null) return bar;
    return Row(children: [
      Expanded(child: bar),
      const SizedBox(width: 10),
      Text(
        trailing ?? '$rr RR',
        style: AppType.bodyS.copyWith(fontFamily: AppType.display, fontWeight: FontWeight.w700, color: color),
      ),
    ]);
  }
}

/// Circular progress with a centred child.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.color, this.size = 64, this.stroke = 7, this.child});
  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0.0, 1.0), color, stroke),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.stroke);
  final double value;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.surfaceTop);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [Color.lerp(color, Colors.black, 0.3)!, color],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value || old.color != color;
}

enum DayDotState { empty, trained, rest, today, future }

/// The calendar icons: a dumbbell on workout days, a moon on the rest days that kept the streak alive.
const IconData workoutDayIcon = Icons.fitness_center_rounded;
const IconData restDayIcon = Icons.bedtime_rounded;
const Color restDayColor = Color(0xFF8FA3FF);

/// Monday → Sunday dots: the days you trained this week.
class DayDots extends StatelessWidget {
  const DayDots({super.key, required this.states});
  final List<DayDotState> states;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Column(mainAxisSize: MainAxisSize.min, children: [
            _dot(states[i]),
            const SizedBox(height: 4),
            Text(_labels[i], style: AppType.label.copyWith(fontSize: 10, color: AppColors.textTertiary, letterSpacing: 0)),
          ]),
      ],
    );
  }

  Widget _dot(DayDotState s) {
    const size = 26.0;
    switch (s) {
      case DayDotState.trained:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 8)],
          ),
          child: const Icon(workoutDayIcon, size: 15, color: Color(0xFF06210F)),
        );
      case DayDotState.rest:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: AppColors.surfaceTop, shape: BoxShape.circle, border: Border.all(color: restDayColor.withValues(alpha: 0.5))),
          child: const Icon(restDayIcon, size: 14, color: restDayColor),
        );
      case DayDotState.today:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primary, width: 2)),
        );
      case DayDotState.future:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.outline)),
        );
      case DayDotState.empty:
        return Container(width: size, height: size, decoration: const BoxDecoration(color: AppColors.surfaceTop, shape: BoxShape.circle));
    }
  }
}

/// Under a calendar: what the dumbbell and the moon mean.
class StreakLegend extends StatelessWidget {
  const StreakLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textSecondary);
    Widget item(IconData icon, Color color, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(text, style: style),
        ]);
    return Wrap(
      key: const ValueKey('streak-legend'),
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 4,
      children: [
        item(workoutDayIcon, AppColors.primary, 'Workout'),
        item(restDayIcon, restDayColor, 'Rest day, streak kept'),
      ],
    );
  }
}

/// Shimmering placeholder block.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 10});
  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.6 + 3.2 * _c.value - 0.5, 0),
            end: Alignment(-1.6 + 3.2 * _c.value + 0.5, 0),
            colors: const [AppColors.surfaceHigh, AppColors.surfaceTop, AppColors.surfaceHigh],
          ),
        ),
      ),
    );
  }
}

/// A screen-shaped skeleton: a few card-sized blocks.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.items = 4, this.itemHeight = 92, this.padding = const EdgeInsets.all(16)});
  final int items;
  final double itemHeight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true, // safe inside other scrollables
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      children: [
        for (var i = 0; i < items; i++)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Skeleton(height: itemHeight, radius: Radii.card)),
      ],
    );
  }
}

/// Integer that counts up to [value].
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, this.from = 0, this.style, this.prefix = '', this.suffix = '', this.duration = const Duration(milliseconds: 1400)});
  final int value;
  final int from;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from.toDouble(), end: value.toDouble()),
      duration: motion(context, duration),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text('$prefix${v.round()}$suffix', style: style),
    );
  }
}

/// 56 px primary action.
class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, this.icon, this.onPressed, this.busy = false, this.color});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return SizedBox(
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.control),
          boxShadow: onPressed == null ? null : [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(backgroundColor: c, minimumSize: const Size.fromHeight(60)),
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF06210F)))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (icon != null) ...[Icon(icon, size: 24), const SizedBox(width: 8)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ]),
        ),
      ),
    );
  }
}

/// − value + with large buttons; long-press repeats. Tap the value to type it.
class StepperBox extends StatefulWidget {
  const StepperBox({super.key, required this.value, required this.onMinus, required this.onPlus, this.unit, this.onTapValue, this.dense = false});
  final String value;
  final String? unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onTapValue;
  final bool dense;

  @override
  State<StepperBox> createState() => _StepperBoxState();
}

class _StepperBoxState extends State<StepperBox> {
  Timer? _repeat;

  void _start(VoidCallback f) {
    f();
    HapticFeedback.selectionClick();
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 110), (_) => f());
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Widget _btn(IconData icon, VoidCallback f) {
    final size = widget.dense ? 44.0 : 52.0;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        f();
      },
      onLongPressStart: (_) => _start(f),
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surfaceTop,
          borderRadius: BorderRadius.circular(Radii.control - 2),
          border: Border.all(color: AppColors.outlineBright),
        ),
        child: Icon(icon, size: 24, color: AppColors.textPrimary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(children: [
        _btn(Icons.remove_rounded, widget.onMinus),
        Expanded(
          child: GestureDetector(
            onTap: widget.onTapValue,
            behavior: HitTestBehavior.opaque,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(widget.value, style: AppType.number.copyWith(fontSize: widget.dense ? 20 : 24)),
              ),
              if (widget.unit != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(widget.unit!,
                      maxLines: 1, softWrap: false, style: AppType.label.copyWith(fontSize: 10, letterSpacing: 0.6, color: AppColors.textTertiary)),
                ),
            ]),
          ),
        ),
        _btn(Icons.add_rounded, widget.onPlus),
      ]),
    );
  }
}

enum GuardrailTone { override, egoFlag, info }

/// Firm but not annoying: a coloured stripe, one line, optional details on tap.
class GuardrailBanner extends StatefulWidget {
  const GuardrailBanner({super.key, required this.tone, required this.title, this.details});
  final GuardrailTone tone;
  final String title;
  final String? details;

  @override
  State<GuardrailBanner> createState() => _GuardrailBannerState();
}

class _GuardrailBannerState extends State<GuardrailBanner> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (widget.tone) {
      GuardrailTone.override => (AppColors.warning, Icons.warning_amber_rounded),
      GuardrailTone.egoFlag => (AppColors.danger, Icons.lock_rounded),
      GuardrailTone.info => (AppColors.accent, Icons.info_outline_rounded),
    };
    return InkWell(
      onTap: widget.details == null ? null : () => setState(() => _open = !_open),
      borderRadius: BorderRadius.circular(Radii.control),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title, style: AppType.bodyS.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
            if (widget.details != null)
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textSecondary, size: 20),
          ]),
          if (_open && widget.details != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Text(widget.details!, style: AppType.bodyS.copyWith(color: AppColors.textSecondary)),
            ),
        ]),
      ),
    );
  }
}
