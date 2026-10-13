import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/load_types.dart';

void main() {
  /// id → (name, equipment) from the bundled library.
  final lib = <String, (String, String?)>{};
  for (final e in (jsonDecode(File('assets/exercises.json').readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>()) {
    lib[e['id'] as String] = (e['name'] as String, e['equipment'] as String?);
  }
  for (final e in ((jsonDecode(File('assets/extra_exercises.json').readAsStringSync()) as Map<String, dynamic>)['exercises'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    lib[e['id'] as String] = (e['name'] as String, e['equipment'] as String?);
  }
  LoadType of(String id, {bool assisted = false}) => classifyLoad(name: lib[id]!.$1, equipment: lib[id]!.$2, assisted: assisted);

  group('classification (names + dataset equipment)', () {
    test('one loading horn: T-bar row, pendulum squat, landmine', () {
      expect(of('Lying_T-Bar_Row'), LoadType.plateOneSide);
      expect(of('sp_pendulum_squat'), LoadType.plateOneSide);
      expect(classifyLoad(name: 'Landmine press', equipment: 'barbell'), LoadType.plateOneSide);
      expect(classifyLoad(name: 'T-Bar Row with Handle', equipment: 'barbell'), LoadType.plateOneSide);
    });

    test('plates on both sides: Smith, leg press, hack squat, sled calf press, leverage presses and rows', () {
      expect(of('Smith_Machine_Bench_Press'), LoadType.plateBothSides);
      expect(classifyLoad(name: 'Smith Machine Overhead Shoulder Press', equipment: 'machine'), LoadType.plateBothSides);
      expect(classifyLoad(name: 'Leg Press', equipment: 'machine'), LoadType.plateBothSides);
      expect(classifyLoad(name: 'Hack Squat', equipment: 'machine'), LoadType.plateBothSides);
      expect(classifyLoad(name: 'Calf Press On The Leg Press Machine', equipment: 'machine'), LoadType.plateBothSides);
      expect(of('Leverage_Chest_Press'), LoadType.plateBothSides);
      expect(classifyLoad(name: 'Leverage Iso Row', equipment: 'machine'), LoadType.plateBothSides);
    });

    test('pin machines and cables are stacks', () {
      expect(of('Butterfly'), LoadType.stack);
      expect(of('Lying_Leg_Curls'), LoadType.stack);
      expect(of('Leg_Extensions'), LoadType.stack);
      expect(of('Triceps_Pushdown'), LoadType.stack);
      expect(classifyLoad(name: 'Standing Machine Lateral Raise', equipment: 'machine'), LoadType.stack);
    });

    test('barbell, dumbbell, bodyweight, assisted', () {
      expect(of('Stiff-Legged_Barbell_Deadlift'), LoadType.barbell);
      expect(of('EZ-Bar_Curl'), LoadType.barbell);
      expect(of('sp_db_incline_y_raise'), LoadType.dumbbell);
      expect(of('Decline_Crunch'), LoadType.bodyweight);
      expect(classifyLoad(name: 'Assisted Pull-Up (Machine)', equipment: 'machine', assisted: true), LoadType.assisted);
    });

    test('a sled drag is not a plate machine (only machines named sled count)', () {
      expect(classifyLoad(name: 'Sled Drag - Harness', equipment: 'other'), LoadType.other);
    });
  });

  group('steps from the smallest plate (2.5 kg)', () {
    const gym = GymEquipment();
    test('default smallest plate is 2.5 kg', () => expect(gym.smallestPlate, 2.5));

    test('one-sided = one plate: 2.5 kg steps', () {
      final g = gym.gridFor(exerciseId: 'tbar', type: LoadType.plateOneSide);
      expect(g.values.take(4), [2.5, 5, 7.5, 10]);
      expect(g.next(55), 57.5);
      expect(gym.stepFor('tbar', LoadType.plateOneSide), 2.5);
    });

    test('two-sided = a pair: 5 kg steps; barbell 5 kg from the 20 kg bar', () {
      final smith = gym.gridFor(exerciseId: 'smith', type: LoadType.plateBothSides);
      expect(smith.values.take(3), [5, 10, 15]);
      expect(smith.next(55), 60);
      final bb = gym.gridFor(exerciseId: 'bb', type: LoadType.barbell);
      expect(bb.values.take(3), [20, 25, 30]);
      expect(gym.stepFor('smith', LoadType.plateBothSides), 5);
    });

    test('stacks keep the 5 kg default and the per-exercise override', () {
      expect(gym.gridFor(exerciseId: 'pec', type: LoadType.stack).values.take(3), [5, 10, 15]);
      const custom = GymEquipment(perExercise: {'pec': StackSpec(start: 3, step: 7)});
      expect(custom.gridFor(exerciseId: 'pec', type: LoadType.stack).values.take(3), [3, 10, 17]);
    });

    test('the smallest plate is a setting: 1.25 kg plates halve the steps', () {
      const fine = GymEquipment(smallestPlate: 1.25);
      expect(fine.stepFor('x', LoadType.plateOneSide), 1.25);
      expect(fine.stepFor('x', LoadType.plateBothSides), 2.5);
    });

    test('a hand-picked load type wins over the classification, and survives a round trip', () {
      const g = GymEquipment(typeOverrides: {'press': LoadType.plateOneSide});
      expect(g.typeFor('press', LoadType.stack), LoadType.plateOneSide);
      expect(g.gridFor(exerciseId: 'press', type: LoadType.stack).next(40), 42.5);
      final back = GymEquipment.decode(g.encode());
      expect(back.typeOverrides, {'press': LoadType.plateOneSide});
    });

    test('weights you have logged exist even when off the lattice (a 52.5 kg T-bar on a pair-step machine)', () {
      final g = gym.gridFor(exerciseId: 'smith', type: LoadType.plateBothSides, logged: [52.5]);
      expect(g.contains(52.5), isTrue);
      expect(g.next(52.5), 55);
    });

    test('old settings without load types decode with the new defaults', () {
      final old = GymEquipment.decode('{"dumbbells":[2.5,5],"stack":{"start":5,"step":5},"per_exercise":{"a":{"start":2,"step":7}}}');
      expect(old.smallestPlate, 2.5);
      expect(old.perExercise['a'], const StackSpec(start: 2, step: 7));
      expect(old.typeOverrides, isEmpty);
    });
  });
}
