import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/live_activity/live_activity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

/// Which exercise and set follow the rest (the Live Activity's text).
class RestPreview {
  const RestPreview({required this.workoutName, required this.exerciseName, required this.nextTarget});
  final String workoutName;
  final String exerciseName;
  final String nextTarget;
}

/// Starts, adjusts and cancels the rest timer. The end time lives in settings so it survives
/// the app being killed, and a local notification is scheduled for the end.
final restTimerProvider = Provider<RestTimerController>((ref) => RestTimerController(ref));

class RestTimerController {
  RestTimerController(this._ref);
  final Ref _ref;

  /// What the Live Activity shows for the running rest (kept so it can be re-shown after the app was in the
  /// background: iOS lets it run out on its own there).
  RestActivity? _activity;

  /// No-op for 0 s (first exercise of a superset: go straight to the partner).
  Future<void> start(int seconds, {RestPreview? preview}) async {
    if (seconds <= 0) return;
    final now = _ref.read(clockProvider)();
    final endsAt = now.add(Duration(seconds: seconds));
    await _ref.read(settingsControllerProvider).setRestTimer(endsAt, seconds);
    await _ref.read(notificationServiceProvider).scheduleRestDone(endsAt);
    if (preview == null) {
      _activity = null;
      await _ref.read(liveActivityProvider).end();
      return;
    }
    _activity = RestActivity(
      workoutName: preview.workoutName,
      exerciseName: preview.exerciseName,
      nextTarget: preview.nextTarget,
      startsAt: now,
      endsAt: endsAt,
    );
    await _ref.read(liveActivityProvider).startRest(_activity!);
  }

  /// Back in the foreground with a rest still running: show the Live Activity again if iOS let it go.
  Future<void> resync() async {
    final a = _activity, endsAt = _ref.read(currentSettingsProvider).restEndsAt;
    if (a == null || endsAt == null || !endsAt.isAfter(_ref.read(clockProvider)())) return;
    await _ref.read(liveActivityProvider).startRest(a.withEnd(endsAt));
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
    final a = _activity;
    if (a != null) {
      _activity = a.withEnd(next);
      await _ref.read(liveActivityProvider).startRest(_activity!);
    }
  }

  /// When the running rest was skipped (null if it wasn't): the rest taken ends there, not at the next ✓.
  DateTime? _skippedAt;

  /// The skip time, once, if it came after [since] (the previous set's ✓).
  DateTime? takeSkip(DateTime since) {
    final at = _skippedAt;
    _skippedAt = null;
    return at != null && at.isAfter(since) ? at : null;
  }

  /// Skip: ends the rest now and remembers when, for the rest marker between sets.
  Future<void> skip() async {
    _skippedAt = _ref.read(clockProvider)();
    await stop();
  }

  /// Rest over, skipped, the next set started or the workout finished: timer, notification and Live Activity go.
  Future<void> stop() async {
    _activity = null;
    await _ref.read(settingsControllerProvider).setRestTimer(null, null);
    await _ref.read(notificationServiceProvider).cancelRest();
    await _ref.read(liveActivityProvider).end();
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
                _TimerButton(label: 'Skip', filled: true, onTap: controller.skip),
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
