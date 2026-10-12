import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/tutorials/data/media_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('matching: overrides applied, manual picks survive re-matching, export format', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ex = ExerciseRepository(db);
    await ex.ensureSeeded(jsonOverride: File('assets/exercises.json').readAsStringSync());
    final catalog = await ex.watchCatalog().first;
    final repo = MediaRepository(db);
    final now = DateTime(2026, 10, 12);

    await repo.ensureMatched(catalog, now: now);
    final rows = await db.select(db.mediaMatches).get();
    expect(rows.length, catalog.length);

    final squat = (await repo.match('Barbell_Squat'))!;
    expect(squat.source, 'override');
    expect(squat.edbId, 'qXTaZnJ');
    expect(squat.gifUrl, startsWith('https://static.exercisedb.dev/media/'));
    final face = (await repo.match('Face_Pull'))!;
    expect(face.source, 'override');
    expect(face.edbId, isNull, reason: 'null override = no demo');
    // Barbell Curl was merged with its ExerciseDB V1 duplicate: it uses that GIF, no guessing.
    expect((await repo.match('Barbell_Curl'))!.source, 'library');

    // Manual pick, then force a re-match (version bump): the pick is kept.
    final edb = await MediaRepository.loadEdb();
    await repo.setManual('Barbell_Curl', edb.firstWhere((e) => e.id == 'EIeI8Vf'), now: now);
    await db.putSetting('media_match_version', '0');
    await repo.ensureMatched(catalog, now: now);
    expect((await repo.match('Barbell_Curl'))!.edbId, 'EIeI8Vf');
    expect((await repo.match('Barbell_Curl'))!.source, 'manual');

    final exported = jsonDecode(await repo.exportOverrides()) as Map<String, dynamic>;
    expect(exported['schema_version'], 1);
    final o = exported['overrides'] as Map<String, dynamic>;
    expect(o['Barbell_Curl'], 'EIeI8Vf');
    expect(o.containsKey('Face_Pull'), isTrue);
    expect(o['Face_Pull'], isNull);
  });
}
