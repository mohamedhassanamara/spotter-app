import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/program/data/program_repository.dart';
import 'package:spotter/features/program/domain/program.dart';
import 'package:spotter/features/program/domain/program_videos.dart';
import 'package:spotter/features/ranks/data/rank_exclusions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const newId = ProgramRepository.singleArmReverseFlyId;

  Future<List<RoutineExercise>> pull(AppDatabase db) async {
    final r = await (db.select(db.routines)..where((t) => t.name.equals('Pull'))).getSingle();
    return (db.select(db.routineExercises)
          ..where((t) => t.routineId.equals(r.id))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  test('a fresh install has Machine Single-Arm Reverse Fly in Pull, same slot, with the program prescription and Jeff\'s video', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    final rows = await pull(db);
    final i = rows.indexWhere((r) => r.exerciseId == newId);
    expect(i, 4, reason: 'same position as the old Machine Reverse Fly');
    expect(rows.any((r) => r.exerciseId == 'Reverse_Machine_Flyes'), isFalse);
    final row = rows[i];
    expect(row.displayName, 'Machine Single-Arm Reverse Fly');
    expect(row.targetSets, 2);
    expect((row.repMin, row.repMax), (20, 20));
    expect(row.restSeconds, 120);
    expect(jsonDecode(row.programSlots!), ['pull_06', 'pull_07']);

    final program = Program.fromJson(jsonDecode(File('assets/programs/min_max_canonical.json').readAsStringSync()) as Map<String, dynamic>);
    final first = program.slot('pull_06')!, second = program.slot('pull_07')!;
    expect((first.repRange.min, second.repRange.min), (20, 10));
    expect((first.warmupSets.min, first.warmupSets.max), (0, 1));
    expect(first.rir, [0]);
    expect(second.rir, [0]);
    expect((first.rest!.minSeconds, first.rest!.maxSeconds), (60, 120));

    final catalog = await ExerciseRepository(db).watchCatalog().first;
    final videos = programVideos(
      program: program,
      rows: [
        for (final r in rows)
          RoutineVideoRow(
              exerciseId: r.exerciseId,
              name: r.displayName ?? r.exerciseId,
              relation: r.programRelation,
              programExercise: r.programExercise,
              slotIds: (jsonDecode(r.programSlots ?? '[]') as List<dynamic>).cast<String>()),
      ],
      catalog: catalog,
    );
    expect(videos[newId]?.programName, '1-Arm Reverse Pec Deck');
  });

  test('an existing install is migrated in place (once), keeping your edits and the position', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    final id = (await pull(db))[4].id;
    // Back to the state of the phone: the two-arm exercise, with a set count you changed.
    await (db.update(db.routineExercises)..where((t) => t.id.equals(id)))
        .write(const RoutineExercisesCompanion(exerciseId: Value('Reverse_Machine_Flyes'), displayName: Value('Machine Reverse Fly'), targetSets: Value(3)));
    await db.deleteSetting(ProgramRepository.singleArmReverseFlyKey);
    expect(await ProgramRepository.ensureSingleArmReverseFly(db), isTrue);
    var rows = await pull(db);
    expect(rows[4].id, id);
    expect(rows[4].exerciseId, newId);
    expect(rows[4].displayName, 'Machine Single-Arm Reverse Fly');
    expect(rows[4].targetSets, 3, reason: 'your set count is kept');
    expect(await ProgramRepository.ensureSingleArmReverseFly(db), isFalse, reason: 'runs once');

    // The two-arm one is no longer in a routine: off for ranks unless you do it again or switch it on.
    expect((await RankExclusions(db).load()).contains('Reverse_Machine_Flyes'), isTrue);
    expect((await RankExclusions(db).load()).contains(newId), isFalse);
    rows = await pull(db);
    expect(rows.length, 6);
  });
}
