import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/live_activity/live_activity_service.dart';

/// The lock-screen layout of the workout's Live Activity, rendered by the native view at the real width: every phase fits the ~160 pt a
/// Live Activity gets (nothing cut off at the top or bottom), also with a very long exercise name and four warm-ups. PNGs go to SHOTS_DIR.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const lockScreenHeight = 160.0;
  final start = DateTime.now().subtract(const Duration(minutes: 23, seconds: 41));
  final restStart = DateTime.now().subtract(const Duration(seconds: 30));

  WorkoutActivity activity({
    required String phase,
    String exercise = 'Chest Press',
    String next = 'Next: working set 65 kg × 6',
    String setLabel = 'Set 1 of 3',
    List<ActivityWarmup> warmups = const [],
    int more = 0,
    bool rest = false,
  }) =>
      WorkoutActivity(
        phase: phase,
        workoutName: 'Upper',
        exerciseName: exercise,
        nextTarget: next,
        setLabel: setLabel,
        workoutStart: start,
        restStart: rest ? restStart : null,
        restEnd: rest ? restStart.add(const Duration(seconds: 90)) : null,
        warmups: warmups,
        warmupsMore: more,
      );

  const long = 'Smith Machine Overhead Shoulder Press (Seated, Close Grip, Pause at the Bottom)';
  final warmups4 = const [ActivityWarmup('25×6', true), ActivityWarmup('40×4', false), ActivityWarmup('50×3', false), ActivityWarmup('60×2', false)];

  final cases = <String, WorkoutActivity>{
    'warmup': activity(phase: 'warmup', setLabel: 'Warm-up 2 of 4', next: 'Next: 40 kg × 4', warmups: warmups4),
    'warmup-long-name-4-chips': activity(phase: 'warmup', exercise: long, setLabel: 'Warm-up 2 of 4', next: 'Next: 40 kg × 4', warmups: warmups4),
    'working': activity(phase: 'working', next: 'Next: working set 65 kg × 6'),
    'working-long-name': activity(phase: 'working', exercise: long, setLabel: 'Set 3 of 3', next: 'Next: drop set 52.5 kg × 12'),
    'rest-after-last-warmup': activity(phase: 'rest', setLabel: 'Set 1 of 3', next: 'Next: working set 65 kg × 6', rest: true, warmups: const [
      ActivityWarmup('25×6', true), ActivityWarmup('40×4', true), ActivityWarmup('50×3', true), ActivityWarmup('60×2', true)
    ]),
    'rest-long-name': activity(phase: 'rest', exercise: long, setLabel: 'Set 2 of 3', next: 'Next: working set 125.5 kg × 12', rest: true),
    'rest-with-chips': activity(phase: 'rest', exercise: long, setLabel: 'Warm-up 4 of 4', next: 'Next: working set 65 kg × 6', rest: true, warmups: warmups4, more: 2),
    'done': activity(phase: 'working', exercise: 'Workout', setLabel: '', next: 'Last set done. Finish when ready.'),
  };

  testWidgets('every phase of the Live Activity fits the lock screen (≈160 pt) and renders', (tester) async {
    final native = ChannelLiveActivityService();
    const hostDir = String.fromEnvironment('SHOTS_DIR');
    for (final e in cases.entries) {
      final r = await tester.runAsync(() => native.renderPreview(e.value));
      expect(r, isNotNull, reason: '${e.key}: the native renderer answers');
      debugPrint('LAYOUT ${e.key}: ${r!.height.toStringAsFixed(1)} pt');
      expect(r.height, lessThanOrEqualTo(lockScreenHeight), reason: '${e.key} must fit in $lockScreenHeight pt (it asks for ${r.height})');
      expect(r.height, greaterThan(60), reason: '${e.key} rendered something');
      if (hostDir.isNotEmpty) {
        final dir = Directory(hostDir)..createSync(recursive: true);
        File('${dir.path}/${e.key}.png').writeAsBytesSync(r.png);
      }
    }
  });
}
