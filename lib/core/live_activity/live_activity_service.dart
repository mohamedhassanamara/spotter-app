import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One warm-up line on the lock screen.
class ActivityWarmup {
  const ActivityWarmup(this.text, this.done);
  final String text;
  final bool done;

  @override
  bool operator ==(Object other) => other is ActivityWarmup && other.text == text && other.done == done;
  @override
  int get hashCode => Object.hash(text, done);
}

/// Everything the lock screen / Dynamic Island shows for a workout. The elapsed time and the rest countdown are drawn by
/// the system from [workoutStart] and [restStart]/[restEnd], so nothing needs updating while the phone is locked.
class WorkoutActivity {
  const WorkoutActivity({
    required this.phase,
    required this.workoutName,
    required this.exerciseName,
    required this.nextTarget,
    required this.setLabel,
    required this.workoutStart,
    this.restStart,
    this.restEnd,
    this.warmups = const [],
    this.warmupsMore = 0,
  });

  /// 'warmup' | 'working' | 'rest'
  final String phase;
  final String workoutName;
  final String exerciseName;

  /// The next set's target, e.g. "Set 3 · 80 kg × 8".
  final String nextTarget;

  /// "Warm-up 2 of 3", "Set 2 of 3"; empty when there is nothing to count.
  final String setLabel;
  final DateTime workoutStart;
  final DateTime? restStart;
  final DateTime? restEnd;
  final List<ActivityWarmup> warmups;
  final int warmupsMore;

  @override
  bool operator ==(Object other) =>
      other is WorkoutActivity &&
      other.phase == phase &&
      other.workoutName == workoutName &&
      other.exerciseName == exerciseName &&
      other.nextTarget == nextTarget &&
      other.setLabel == setLabel &&
      other.workoutStart == workoutStart &&
      other.restStart == restStart &&
      other.restEnd == restEnd &&
      other.warmupsMore == warmupsMore &&
      listEquals(other.warmups, warmups);
  @override
  int get hashCode => Object.hash(phase, workoutName, exerciseName, nextTarget, setLabel, workoutStart, restStart, restEnd, warmupsMore);
}

/// What the running rest shows (kept by the rest timer; the workout's activity folds it in).
class RestActivity {
  const RestActivity({
    required this.workoutName,
    required this.exerciseName,
    required this.nextTarget,
    required this.startsAt,
    required this.endsAt,
  });

  final String workoutName;
  final String exerciseName;
  final String nextTarget;
  final DateTime startsAt;
  final DateTime endsAt;

  RestActivity withEnd(DateTime end) =>
      RestActivity(workoutName: workoutName, exerciseName: exerciseName, nextTarget: nextTarget, startsAt: startsAt, endsAt: end);
}

/// iOS Live Activity for the whole workout (native WidgetKit extension in ios/SpotterLiveActivity).
abstract class LiveActivityService {
  /// Starts the activity, or updates it when one is running.
  Future<void> sync(WorkoutActivity activity);

  /// Removes it now (workout finished or discarded).
  Future<void> end();
}

class NoopLiveActivityService implements LiveActivityService {
  const NoopLiveActivityService();
  @override
  Future<void> sync(WorkoutActivity activity) async {}
  @override
  Future<void> end() async {}
}

class ChannelLiveActivityService implements LiveActivityService {
  ChannelLiveActivityService([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('spotter/live_activity');
  final MethodChannel _channel;

  static Map<String, Object?> _args(WorkoutActivity a) => {
        'phase': a.phase,
        'workoutName': a.workoutName,
        'exerciseName': a.exerciseName,
        'nextTarget': a.nextTarget,
        'setLabel': a.setLabel,
        'workoutStartMillis': a.workoutStart.millisecondsSinceEpoch.toDouble(),
        'restStartMillis': a.restStart?.millisecondsSinceEpoch.toDouble(),
        'restEndMillis': a.restEnd?.millisecondsSinceEpoch.toDouble(),
        'warmups': [for (final w in a.warmups) {'text': w.text, 'done': w.done}],
        'warmupsMore': a.warmupsMore,
      };

  @override
  Future<void> sync(WorkoutActivity a) => _call('sync', _args(a));

  /// Renders the native lock-screen view for [a] at [width] pt (361 on a 6.3" iPhone): PNG bytes and the height the layout asks for
  /// (a Live Activity has about 160 pt). Used by the integration tests to check and screenshot the layout.
  Future<({Uint8List png, double height})?> renderPreview(WorkoutActivity a, {double width = 361, double restFraction = 0.4}) async {
    final r = await _call('renderPreview', {..._args(a), 'width': width, 'restFraction': restFraction}) as Map<Object?, Object?>?;
    if (r == null) return null;
    return (png: r['png']! as Uint8List, height: (r['height']! as num).toDouble());
  }

  @override
  Future<void> end() => _call('end');

  /// Running workout activities (native count; used by the integration tests).
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
