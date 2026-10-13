import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/program/domain/program.dart';
import 'package:spotter/features/program/domain/program_videos.dart';

Map<String, ExerciseInfo> catalog() {
  final raw = [
    ...(jsonDecode(File('assets/exercises.json').readAsStringSync()) as List<dynamic>),
    ...((jsonDecode(File('assets/extra_exercises.json').readAsStringSync()) as Map<String, dynamic>)['exercises'] as List<dynamic>),
  ].cast<Map<String, dynamic>>();
  return {
    for (final e in raw)
      e['id'] as String: ExerciseInfo(
        id: e['id'] as String,
        name: e['name'] as String,
        primaryMuscles: (e['primaryMuscles'] as List<dynamic>).cast<String>(),
        secondaryMuscles: (e['secondaryMuscles'] as List<dynamic>).cast<String>(),
        equipment: e['equipment'] as String?,
        level: null,
        mechanic: e['mechanic'] as String?,
        category: null,
        instructions: const [],
        images: const [],
        isCustom: false,
        isFavorite: false,
        notes: null,
      ),
  };
}

void main() {
  final program = Program.fromJson(jsonDecode(File('assets/programs/min_max_canonical.json').readAsStringSync()) as Map<String, dynamic>);
  final routines = jsonDecode(File('assets/programs/my_routines.json').readAsStringSync()) as Map<String, dynamic>;
  final rows = [
    for (final r in (routines['routines'] as List<dynamic>).cast<Map<String, dynamic>>())
      for (final e in (r['exercises'] as List<dynamic>).cast<Map<String, dynamic>>())
        RoutineVideoRow(
          exerciseId: e['exercise_id'] as String,
          name: e['name'] as String,
          relation: e['relation'] as String?,
          programExercise: e['program_exercise'] as String?,
          slotIds: (e['program_slots'] as List<dynamic>).cast<String>(),
        ),
  ];
  final videos = programVideos(program: program, rows: rows, catalog: catalog());

  test('every program exercise and substitution has a video from the PDF', () {
    for (final d in program.days) {
      for (final s in d.slots) {
        expect(s.videos.keys.toSet(), {s.exercise, ...s.substitutions}, reason: s.id);
      }
    }
  });

  test("program rows get their own video; my swaps never reuse the replaced exercise's", () {
    expect(videos['Leverage_Chest_Press']!.programName, 'Machine Chest Press');
    for (final swap in ['sp_pendulum_squat', 'Straight-Arm_Pulldown', 'Decline_Crunch']) {
      expect(videos[swap], isNull, reason: '$swap is my swap and the program lists no video for it');
    }
    final hack = program.days.expand((d) => d.slots).firstWhere((s) => s.exercise == 'Hack Squat').videos['Hack Squat']!;
    expect(videos.values.where((v) => v.ref == hack).every((v) => v.programName == 'Hack Squat'), isTrue);
  });

  test('coverage report for my routines', () {
    final lines = [for (final r in rows) '${r.name}: ${videos[r.exerciseId] == null ? 'not found' : 'video found (${videos[r.exerciseId]!.programName})'}'];
    // ignore: avoid_print
    if (Platform.environment['PRINT_VIDEOS'] == '1') print(lines.join('\n'));
    expect(lines.length, rows.length);
  });
}
