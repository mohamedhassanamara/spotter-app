import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/library/domain/name_resolver.dart';

void main() {
  final raw = [
    ...(jsonDecode(File('assets/exercises.json').readAsStringSync()) as List<dynamic>),
    ...((jsonDecode(File('assets/extra_exercises.json').readAsStringSync()) as Map<String, dynamic>)['exercises'] as List<dynamic>),
  ].cast<Map<String, dynamic>>();
  final catalog = [
    for (final e in raw)
      ExerciseInfo(
        id: e['id'] as String,
        name: e['name'] as String,
        primaryMuscles: (e['primaryMuscles'] as List<dynamic>).cast<String>(),
        secondaryMuscles: (e['secondaryMuscles'] as List<dynamic>).cast<String>(),
        equipment: e['equipment'] as String?,
        level: e['level'] as String?,
        mechanic: e['mechanic'] as String?,
        category: e['category'] as String?,
        instructions: (e['instructions'] as List<dynamic>).cast<String>(),
        images: (e['images'] as List<dynamic>).cast<String>(),
        isCustom: false,
        isFavorite: false,
        notes: null,
      ),
  ];
  final r = ExerciseNameResolver(catalog);

  test('exact names win', () {
    expect(r.resolve('Smith Machine Bench Press')!.exercise.id, 'Smith_Machine_Bench_Press');
    expect(r.resolve('Pendulum Squat')!.exercise.id, 'sp_pendulum_squat');
    expect(r.resolve('face pull')!.score, 1);
  });

  test('program substitution names resolve to sensible library exercises', () {
    expect(r.resolve('DB Bench Press')!.exercise.id, 'Dumbbell_Bench_Press');
    expect(r.resolve('Lying Leg Curl')!.exercise.id, 'Lying_Leg_Curls');
    expect(r.resolve('Leg Press')!.exercise.id, 'Leg_Press');
  });

  test('nonsense does not resolve', () {
    expect(r.resolve('Underwater basket weaving'), isNull);
  });
}
