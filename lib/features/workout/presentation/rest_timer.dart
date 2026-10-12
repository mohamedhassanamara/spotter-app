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

    return Material(
      color: done ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surfaceHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProgressBar(value: progress, color: done ? AppColors.primary : AppColors.accent, height: 6),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(done ? Icons.notifications_active_rounded : Icons.timer_outlined,
                      color: done ? AppColors.primary : AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      done ? 'Rest done — go!' : 'Rest ${formatClock(remaining)}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (!done) ...[
                    _TimerButton(label: '−15', onTap: () => controller.adjust(-15)),
                    const SizedBox(width: 8),
                    _TimerButton(label: '+15', onTap: () => controller.adjust(15)),
                    const SizedBox(width: 8),
                  ],
                  _TimerButton(label: done ? 'OK' : 'Skip', onTap: controller.stop, filled: true),
                ],
              ),
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
      minimumSize: const WidgetStatePropertyAll(Size(60, 48)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
    final child = Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16));
    return filled
        ? FilledButton(onPressed: onTap, style: style, child: child)
        : OutlinedButton(onPressed: onTap, style: style, child: child);
  }
}
