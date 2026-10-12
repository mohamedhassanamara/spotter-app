import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

/// Starts, adjusts and cancels the rest timer. The end time lives in settings so it survives
/// the app being killed, and a local notification is scheduled for the end.
final restTimerProvider = Provider<RestTimerController>((ref) => RestTimerController(ref));

class RestTimerController {
  RestTimerController(this._ref);
  final Ref _ref;

  Future<void> start(int seconds) async {
    final endsAt = _ref.read(clockProvider)().add(Duration(seconds: seconds));
    await _ref.read(settingsControllerProvider).setRestTimer(endsAt, seconds);
    await _ref.read(notificationServiceProvider).scheduleRestDone(endsAt);
  }

  Future<void> adjust(int deltaSeconds) async {
    final s = _ref.read(currentSettingsProvider);
    final endsAt = s.restEndsAt;
    if (endsAt == null) return;
    final next = endsAt.add(Duration(seconds: deltaSeconds));
    final now = _ref.read(clockProvider)();
    if (!next.isAfter(now)) return stop();
    await _ref.read(settingsControllerProvider).setRestTimer(next, (s.restTotalSeconds ?? 0) + deltaSeconds);
    await _ref.read(notificationServiceProvider).scheduleRestDone(next);
  }

  Future<void> stop() async {
    await _ref.read(settingsControllerProvider).setRestTimer(null, null);
    await _ref.read(notificationServiceProvider).cancelRest();
  }
}

/// Countdown bar shown at the bottom of the active workout.
class RestTimerBar extends ConsumerStatefulWidget {
  const RestTimerBar({super.key});

  @override
  ConsumerState<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends ConsumerState<RestTimerBar> {
  Timer? _tick;
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(currentSettingsProvider);
    final endsAt = s.restEndsAt;
    if (endsAt == null) {
      _buzzed = false;
      return const SizedBox.shrink();
    }
    final now = ref.watch(clockProvider)();
    final remaining = endsAt.difference(now);
    final total = (s.restTotalSeconds ?? 1).clamp(1, 3600);
    final done = remaining.inMilliseconds <= 0;
    if (done && !_buzzed) {
      _buzzed = true;
      HapticFeedback.heavyImpact();
    }
    final controller = ref.read(restTimerProvider);
    final progress = done ? 1.0 : 1 - remaining.inMilliseconds / (total * 1000);

    final color = done ? AppColors.primary : AppColors.accent;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: color.withValues(alpha: 0.5))),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              ProgressRing(
                value: progress,
                color: color,
                size: 58,
                stroke: 6,
                child: done
                    ? Icon(Icons.notifications_active_rounded, color: color)
                    : Text('${(remaining.inMilliseconds / 1000).ceil()}', style: AppType.number.copyWith(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(done ? 'REST DONE' : 'REST', style: AppType.label.copyWith(color: color)),
                  Text(done ? 'Next set!' : formatClock(remaining), style: AppType.displayL.copyWith(fontSize: 28)),
                ]),
              ),
              if (!done) ...[
                _TimerButton(label: '−15', onTap: () => controller.adjust(-15)),
                const SizedBox(width: 6),
                _TimerButton(label: '+15', onTap: () => controller.adjust(15)),
                const SizedBox(width: 6),
              ],
              _TimerButton(label: done ? 'OK' : 'Skip', onTap: controller.stop, filled: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerButton extends StatelessWidget {
  const _TimerButton({required this.label, required this.onTap, this.filled = false});
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(56, 52)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
    final child = Text(label, style: const TextStyle(fontFamily: AppType.display, fontWeight: FontWeight.w800, fontSize: 16));
    return filled
        ? FilledButton(onPressed: onTap, style: style, child: child)
        : OutlinedButton(onPressed: onTap, style: style, child: child);
  }
}
