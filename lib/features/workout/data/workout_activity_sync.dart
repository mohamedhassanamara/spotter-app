import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/live_activity/live_activity_service.dart';
import '../domain/workout_activity.dart';
import '../presentation/rest_timer.dart';

final workoutActivitySyncProvider = Provider<WorkoutActivitySync>((ref) {
  final sync = WorkoutActivitySync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

/// The only writer of the workout's Live Activity: it rebuilds the activity from the active session and the running rest
/// whenever either changes, and sends it when it differs from what is already showing.
class WorkoutActivitySync {
  WorkoutActivitySync(this._ref);
  final Ref _ref;

  WorkoutActivity? _last;
  bool _ended = false;
  Timer? _restEnd;

  void dispose() => _restEnd?.cancel();

  /// [force] re-sends even when nothing changed (back in the foreground: iOS may have dropped the activity).
  void refresh({bool force = false}) {
    final session = _ref.read(activeSessionProvider).value;
    final service = _ref.read(liveActivityProvider);
    if (session == null || session.session.status != 'active') {
      _restEnd?.cancel();
      if (_last != null || !_ended || force) {
        _last = null;
        _ended = true;
        unawaited(service.end());
      }
      return;
    }
    final catalog = _ref.read(catalogProvider).value ?? const {};
    final rest = _ref.read(restTimerProvider).running;
    final next = buildWorkoutActivity(
      session,
      nameOf: (e) => e.row.displayName ?? catalog[e.row.exerciseId]?.name ?? e.row.exerciseId,
      rest: rest,
    );
    // When the rest runs out the countdown is over: show the workout again without waiting for a tap.
    _restEnd?.cancel();
    if (rest != null) {
      _restEnd = Timer(rest.endsAt.difference(_ref.read(clockProvider)()) + const Duration(milliseconds: 300), refresh);
    }
    if (next == null || (!force && next == _last)) return;
    _last = next;
    _ended = false;
    unawaited(service.sync(next));
  }
}
