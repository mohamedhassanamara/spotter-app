import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/debug/domain/exercise_audit.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';

ExerciseInfo _ex(String id, String name, String? equipment) => ExerciseInfo(
      id: id,
      name: name,
      primaryMuscles: const [],
      secondaryMuscles: const [],
      equipment: equipment,
      level: null,
      mechanic: null,
      category: null,
      instructions: const [],
      images: const [],
      isCustom: false,
      isFavorite: false,
      notes: null,
    );

void main() {
  final standards = RanksRepository.parseStandards(File('assets/strength_standards.json').readAsStringSync());
  final byName = {for (final s in standards) s.name: s};
  StandardVerdict verdict(String name, String? equipment, String standard) => standardVerdict(exercise: _ex('x', name, equipment), standard: byName[standard]);

  group('ranking entry ↔ logged exercise', () {
    test('a different movement or equipment is a mismatch', () {
      expect(verdict('Flat Bench Lying Leg Raise', 'body only', 'Crunch'), StandardVerdict.mismatch, reason: 'a leg raise is not a crunch');
      expect(verdict('Barbell Curl', 'barbell', 'Dumbbell curl'), StandardVerdict.mismatch, reason: 'equipment');
    });

    test('the same movement is ok, in any wording', () {
      expect(verdict('Bent Over Barbell Row', 'barbell', 'Barbell row'), StandardVerdict.ok);
      expect(verdict('One-Arm Dumbbell Row', 'dumbbell', 'Dumbbell row'), StandardVerdict.ok, reason: 'a per-hand standard is one arm at a time');
      expect(verdict('Palms-Down Wrist Curl Over A Bench', 'barbell', 'Barbell reverse wrist curl'), StandardVerdict.ok);
    });

    test('a variant ranked under its family is kept and shown as a variant', () {
      expect(verdict('Reverse Crunch', 'body only', 'Crunch'), StandardVerdict.variant);
      expect(verdict('Dumbbell Walking Lunge', 'dumbbell', 'Dumbbell lunge'), StandardVerdict.variant);
    });

    test('no entry → none', () {
      expect(standardVerdict(exercise: _ex('x', 'Anything', null), standard: null), StandardVerdict.none);
    });

    test('the leg raise has its own entry (it used to be ranked as a crunch)', () {
      expect(byName['Lying leg raise']!.exerciseIds, ['Flat_Bench_Lying_Leg_Raise']);
      expect(byName['Crunch']!.exerciseIds, isNot(contains('Flat_Bench_Lying_Leg_Raise')));
    });
  });
}
