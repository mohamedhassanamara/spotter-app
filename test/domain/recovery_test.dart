import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/recovery/domain/recovery.dart';
import 'package:spotter/features/recovery/domain/recovery_config.dart';

HistSession _session(DateTime at, List<(MuscleTargets, List<LoggedSet>)> exercises, {String name = 'Push'}) => HistSession(
      id: at.millisecondsSinceEpoch,
      name: name,
      routineId: null,
      startedAt: at.subtract(const Duration(hours: 1)),
      endedAt: at,
      notes: '',
      readinessScore: null,
      readinessBand: null,
      xpEarned: 0,
      exercises: [
        for (final (i, (t, sets)) in exercises.indexed)
          HistExercise(
            id: i,
            exerciseId: 'ex$i',
            name: 'Ex $i',
            targets: t,
            equipment: EquipmentKind.other,
            range: const RepRange(8, 12),
            targetSets: sets.length,
            suggestionKind: SuggestionKind.none,
            suggestedWeight: null,
            suggestedReps: null,
            notes: '',
            sets: [for (final (j, s) in sets.indexed) HistSet(id: j, set: s, completedAt: at)],
          ),
      ],
    );

const _chestPress = MuscleTargets({Muscle.lowerChest: 1.0, Muscle.frontDelt: 0.5, Muscle.triceps: 0.3});
const _curl = MuscleTargets({Muscle.biceps: 1.0, Muscle.forearms: 0.3});

List<LoggedSet> _sets(int n, {double rpe = 10}) => List.filled(n, LoggedSet(weight: 50, reps: 10, rpe: rpe));

void main() {
  final now = DateTime(2026, 10, 13, 18);

  group('fatigue per set', () {
    test('effort factors F 1.0 / 1 left 0.85 / 2 left 0.7 / 3+ 0.5; drops 0.5', () {
      expect(setFatigue(const LoggedSet(weight: 50, reps: 10, rpe: 10)), 1.0);
      expect(setFatigue(const LoggedSet(weight: 50, reps: 10, rpe: 9)), 0.85);
      expect(setFatigue(const LoggedSet(weight: 50, reps: 10, rpe: 8)), 0.7);
      expect(setFatigue(const LoggedSet(weight: 50, reps: 10, rpe: 7)), 0.5);
      expect(setFatigue(const LoggedSet(weight: 40, reps: 8, rpe: 10, isDrop: true)), 0.5);
    });
    test('imported sets without effort count as failure; warm-ups add nothing', () {
      expect(setFatigue(const LoggedSet(weight: 50, reps: 10)), 1.0);
      expect(setFatigue(const LoggedSet(weight: 20, reps: 10, isWarmup: true)), 0);
    });
  });

  group('decay', () {
    test('half-life 48 h for large muscles, 30 h for small ones', () {
      expect(decay(8, 48, Muscle.quadriceps), closeTo(4, 1e-9));
      expect(decay(8, 96, Muscle.lats), closeTo(2, 1e-9));
      expect(decay(8, 30, Muscle.biceps), closeTo(4, 1e-9));
      expect(decay(8, 30, Muscle.middleDelt), closeTo(4, 1e-9));
      expect(decay(8, 0, Muscle.biceps), 8);
    });
    test('readiness slows recovery: Yellow ×0.85, Red ×0.7', () {
      expect(RecoveryConfig.readinessSpeed['yellow'], 0.85);
      expect(RecoveryConfig.readinessSpeed['red'], 0.7);
      final green = decay(8, 48, Muscle.glutes);
      final yellow = decay(8, 48, Muscle.glutes, speed: 0.85);
      final red = decay(8, 48, Muscle.glutes, speed: 0.7);
      expect(yellow, greaterThan(green));
      expect(red, greaterThan(yellow));
      expect(red, closeTo(8 * 0.6156, 0.01)); // 0.5^0.7
    });
    test('time until Ready is longer on a Red day', () {
      expect(hoursUntilReady(6, Muscle.quadriceps, speed: 0.7), greaterThan(hoursUntilReady(6, Muscle.quadriceps)));
      expect(hoursUntilReady(0.5, Muscle.quadriceps), 0);
    });
  });

  group('bands', () {
    test('Ready ≥ 90, Recovering 60–89, Fatigued < 60', () {
      expect(RecoveryBand.of(100), RecoveryBand.ready);
      expect(RecoveryBand.of(90), RecoveryBand.ready);
      expect(RecoveryBand.of(89.9), RecoveryBand.recovering);
      expect(RecoveryBand.of(60), RecoveryBand.recovering);
      expect(RecoveryBand.of(59.9), RecoveryBand.fatigued);
      expect(RecoveryBand.of(0), RecoveryBand.fatigued);
    });
  });

  group('state from history', () {
    test('right after 8 hard chest sets chest is Fatigued, delts less so, untouched muscles Ready', () {
      final h = TrainingHistory([_session(now, [(_chestPress, _sets(8))])]);
      final r = computeRecovery(h, now: now);
      expect(r.of(Muscle.lowerChest).band, RecoveryBand.fatigued);
      expect(r.of(Muscle.frontDelt).pct, greaterThan(r.of(Muscle.lowerChest).pct));
      expect(r.of(Muscle.quadriceps).pct, 100);
      expect(r.of(Muscle.quadriceps).band, RecoveryBand.ready);
      expect(r.of(Muscle.lowerChest).lastSession, 'Push');
    });

    test('recovers over the following days; a Red day slows it', () {
      final h = TrainingHistory([_session(now.subtract(const Duration(hours: 48)), [(_chestPress, _sets(8))])]);
      final green = computeRecovery(h, now: now);
      final red = computeRecovery(h, now: now, readinessBand: 'red');
      expect(green.of(Muscle.lowerChest).pct, closeTo(100 * (1 - 4 / 12), 0.5));
      expect(red.of(Muscle.lowerChest).pct, lessThan(green.of(Muscle.lowerChest).pct));
      final later = computeRecovery(h, now: now.add(const Duration(days: 4)));
      expect(later.of(Muscle.lowerChest).band, RecoveryBand.ready);
    });

    test('small muscles recover faster than large ones for the same fatigue', () {
      final h = TrainingHistory([
        _session(now.subtract(const Duration(hours: 40)), [(_chestPress, _sets(6)), (_curl, _sets(6))]),
      ]);
      final r = computeRecovery(h, now: now);
      expect(r.of(Muscle.biceps).pct, greaterThan(r.of(Muscle.lowerChest).pct));
    });

    test('heads-up lists the fatigued primary muscles of a planned workout only', () {
      final h = TrainingHistory([_session(now, [(_chestPress, _sets(10))])]);
      final r = computeRecovery(h, now: now);
      // Front delt (0.5) is a primary too and got 5 units → Fatigued; triceps (0.3) isn't a primary.
      expect(fatiguedPrimaries(r, [_chestPress]), [Muscle.frontDelt, Muscle.lowerChest]);
      expect(fatiguedPrimaries(r, [_curl]), isEmpty);
    });
  });
}
