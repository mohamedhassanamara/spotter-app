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

  /// No-op for 0 s (first exercise of a superset: go straight to the partner).
  Future<void> start(int seconds) async {
    if (seconds <= 0) return;
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

/// The workout header's clock: elapsed time, or "REST 1:26" while resting (tap for the rest sheet).
/// Buzzes once when the rest ends; the local notification covers a locked phone.
class WorkoutClock extends ConsumerStatefulWidget {
  const WorkoutClock({super.key, required this.startedAt});
  final DateTime startedAt;

  @override
  ConsumerState<WorkoutClock> createState() => _WorkoutClockState();
}

class _WorkoutClockState extends ConsumerState<WorkoutClock> {
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
    final now = ref.watch(clockProvider)();
    final endsAt = s.restEndsAt;
    final remaining = endsAt?.difference(now);
    if (endsAt == null) _buzzed = false;
    if (remaining != null && remaining.inMilliseconds <= 0) {
      if (!_buzzed) {
        _buzzed = true;
        HapticFeedback.heavyImpact();
        WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(restTimerProvider).stop());
      }
    }
    final resting = remaining != null && remaining.inMilliseconds > 0;
    final text = resting ? 'REST ${formatClock(remaining)}' : formatClock(now.difference(widget.startedAt));
    return InkWell(
      key: const ValueKey('workout-clock'),
      borderRadius: BorderRadius.circular(Radii.chip),
      onTap: resting ? () => showRestSheet(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: resting
            ? BoxDecoration(color: AppColors.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(Radii.chip))
            : null,
        child: Text(
          text,
          style: AppType.title.copyWith(fontSize: 18, color: resting ? AppColors.accent : AppColors.primary, fontFeatures: AppType.tabular),
        ),
      ),
    );
  }
}

/// Small sheet with the progress ring, −15 / +15 and Skip. Never full screen.
Future<void> showRestSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _RestSheet(),
    );

class _RestSheet extends ConsumerStatefulWidget {
  const _RestSheet();

  @override
  ConsumerState<_RestSheet> createState() => _RestSheetState();
}

class _RestSheetState extends ConsumerState<_RestSheet> {
  Timer? _tick;
  bool _closing = false;

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
    final controller = ref.read(restTimerProvider);
    if (endsAt == null) {
      // Rest ended or was skipped: close this sheet once (never the route under it).
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).pop();
        });
      }
      return const SizedBox(height: 120);
    }
    final remaining = endsAt.difference(ref.watch(clockProvider)());
    final total = (s.restTotalSeconds ?? 1).clamp(1, 3600);
    final progress = (1 - remaining.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Row(
          children: [
            ProgressRing(
              value: progress,
              color: AppColors.accent,
              size: 72,
              stroke: 7,
              child: Text(formatClock(remaining.isNegative ? Duration.zero : remaining), style: AppType.number.copyWith(fontSize: 18)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _TimerButton(label: '−15', onTap: () => controller.adjust(-15)),
                const SizedBox(width: 8),
                _TimerButton(label: '+15', onTap: () => controller.adjust(15)),
                const SizedBox(width: 8),
                _TimerButton(label: 'Skip', filled: true, onTap: controller.stop),
              ]),
            ),
          ],
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
