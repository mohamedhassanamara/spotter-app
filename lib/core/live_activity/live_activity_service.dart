import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the lock screen / Dynamic Island shows during a rest.
class RestActivity {
  const RestActivity({
    required this.workoutName,
    required this.exerciseName,
    required this.nextTarget,
    required this.startsAt,
    required this.endsAt,
  });

  final String workoutName;

  /// The exercise coming up.
  final String exerciseName;

  /// The next set's target, e.g. "Set 3 · 80 kg × 8".
  final String nextTarget;
  final DateTime startsAt;
  final DateTime endsAt;

  RestActivity withEnd(DateTime end) =>
      RestActivity(workoutName: workoutName, exerciseName: exerciseName, nextTarget: nextTarget, startsAt: startsAt, endsAt: end);
}

/// iOS Live Activity for the rest timer (native WidgetKit extension in ios/SpotterLiveActivity). The
/// countdown is a system timer text, so nothing updates it while the phone is locked.
abstract class LiveActivityService {
  /// Starts the activity, or updates it when one is running.
  Future<void> startRest(RestActivity activity);

  /// Removes it now (rest over or skipped, next set started, workout finished).
  Future<void> end();
}

class NoopLiveActivityService implements LiveActivityService {
  const NoopLiveActivityService();
  @override
  Future<void> startRest(RestActivity activity) async {}
  @override
  Future<void> end() async {}
}

class ChannelLiveActivityService implements LiveActivityService {
  ChannelLiveActivityService([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('spotter/live_activity');
  final MethodChannel _channel;

  @override
  Future<void> startRest(RestActivity a) => _call('start', {
        'workoutName': a.workoutName,
        'exerciseName': a.exerciseName,
        'nextTarget': a.nextTarget,
        'startMillis': a.startsAt.millisecondsSinceEpoch.toDouble(),
        'endMillis': a.endsAt.millisecondsSinceEpoch.toDouble(),
      });

  @override
  Future<void> end() => _call('end');

  /// Running rest activities (native count; used by the integration tests).
  Future<int> activeCount() async => (await _call('activeCount')) as int? ?? 0;

  Future<Object?> _call(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      // Not on iOS (or in a unit test): nothing to show.
    } on PlatformException catch (e) {
      debugPrint('Live Activity $method failed: ${e.message}');
    }
    return null;
  }
}

LiveActivityService defaultLiveActivityService() => !kIsWeb && Platform.isIOS ? ChannelLiveActivityService() : const NoopLiveActivityService();
