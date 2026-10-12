import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../domain/format.dart';

import '../../features/ranks/domain/ranks.dart';
import '../../features/readiness/domain/readiness.dart';
import '../theme/app_theme.dart';

/// Renders an [AsyncValue] with consistent loading and error states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.loading});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => loading ?? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Something went wrong:\n$e', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textSecondary),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(18), this.color, this.borderColor});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: borderColor == null
          ? null
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: borderColor!, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

Color bandColor(ReadinessBand? band) => switch (band) {
      ReadinessBand.green => AppColors.green,
      ReadinessBand.yellow => AppColors.yellow,
      ReadinessBand.red => AppColors.red,
      null => AppColors.textSecondary,
    };

Color tierColor(Tier tier) => tierColors[tier.index];

/// Pill showing a rank label in its tier colour.
class TierBadge extends StatelessWidget {
  const TierBadge(this.score, {super.key, this.large = false});
  final RankScore? score;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final color = s == null ? AppColors.unranked : tierColor(s.tier);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 7 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_rounded, size: large ? 18 : 14, color: color),
          const SizedBox(width: 6),
          Text(
            s?.label ?? 'Unranked',
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: large ? 16 : 13),
          ),
        ],
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color = AppColors.primary, this.height = 10});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: AppColors.surfaceHigh,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// Small labelled number.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.color});
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: color ?? AppColors.textSecondary), const SizedBox(width: 4)],
          Flexible(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color ?? AppColors.textPrimary)),
      ],
    );
  }
}

/// Large − value + control for one-handed entry between sets.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.onTapValue,
    this.unit,
  });

  final String label;
  final String value;
  final String? unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onTapValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            _RoundButton(icon: Icons.remove_rounded, onTap: onMinus),
            Expanded(
              child: InkWell(
                onTap: onTapValue,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Text(value, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                    if (unit != null) Text(unit!, style: const TextStyle(color: AppColors.textSecondary)),
                  ]),
                ),
              ),
            ),
            _RoundButton(icon: Icons.add_rounded, onTap: onPlus),
          ],
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: const CircleBorder(), minimumSize: const Size(64, 64)),
        child: Icon(icon, size: 30),
      ),
    );
  }
}

/// Prompts for a number with a numeric keyboard. Returns null if cancelled.
Future<double?> promptNumber(BuildContext context, {required String title, double? initial, String? suffix, bool decimal = true}) async {
  final controller = TextEditingController(text: initial == null ? '' : _trim(initial));
  final result = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(suffixText: suffix),
        onSubmitted: (v) => Navigator.of(ctx).pop(double.tryParse(v.replaceAll(',', '.'))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(double.tryParse(controller.text.replaceAll(',', '.'))),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<String?> promptText(BuildContext context, {required String title, String initial = '', String? hint, int maxLines = 1}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Save')),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'Confirm', bool destructive = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${d.inMinutes}m';
}

String formatClock(Duration d) {
  final neg = d.isNegative;
  final a = d.abs();
  final m = a.inMinutes, s = a.inSeconds % 60;
  return '${neg ? '-' : ''}$m:${s.toString().padLeft(2, '0')}';
}

