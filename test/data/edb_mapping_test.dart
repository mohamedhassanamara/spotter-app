import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/tutorials/data/edb_v2/edb_client.dart';
import 'package:spotter/features/tutorials/data/edb_v2/edb_mapping_repository.dart';
import 'package:spotter/features/tutorials/domain/edb_v2_mapping.dart';

ExerciseInfo ex(String id, String name, String equipment, List<String> primary) => ExerciseInfo(
      id: id,
      name: name,
      primaryMuscles: primary,
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

class FakeEdb implements EdbApi {
  FakeEdb(this.results, {this.details = const {}});
  final Map<String, List<EdbSearchHit>> results;
  final Map<String, EdbExercise> details;
  final calls = <String>[];

  @override
  Future<List<EdbSearchHit>> search(String query) async {
    calls.add('search:$query');
    return results[query] ?? const [];
  }

  @override
  Future<EdbExercise> exercise(String exerciseId) async {
    calls.add('detail:$exerciseId');
    return details[exerciseId]!;
  }
}

EdbSearchHit hit(String id, String name) => EdbSearchHit(exerciseId: id, name: name);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 10, 12);
  late AppDatabase db;
  late EdbMappingRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EdbMappingRepository(db);
  });
  tearDown(() => db.close());

  final bench = ex('Barbell_Bench_Press_-_Medium_Grip', 'Barbell Bench Press - Medium Grip', 'barbell', ['chest']);
  final fly = ex('Cable_Crossover', 'Cable Crossover', 'cable', ['chest']);

  group('scoring', () {
    test('query drops dataset suffixes', () {
      expect(edbQueryFor(bench), 'Barbell Bench Press');
      expect(edbQueryFor(ex('x', 'Hyperextensions (Back Extensions)', 'other', [])), 'Hyperextensions');
    });

    test('name + equipment; the wrong equipment loses', () {
      final r = scoreCandidates(bench, [(id: 'a', name: 'Dumbbell Bench Press'), (id: 'b', name: 'Barbell Bench Press')]);
      expect(r.first.edbId, 'b');
      expect(isConfident(r), isTrue);
    });

    test('V2 muscle heads map onto our 20 muscles', () {
      expect(muscleForV2('Pectoralis Major Clavicular Head'), Muscle.upperChest);
      expect(muscleForV2('Pectoralis Major Sternal Head'), Muscle.lowerChest);
      expect(muscleForV2('Deltoid Anterior'), Muscle.frontDelt);
      expect(muscleForV2('Deltoid Lateral'), Muscle.middleDelt);
      expect(muscleForV2('Deltoid Posterior'), Muscle.rearDelt);
      expect(muscleForV2('Gluteus Medius'), Muscle.abductors);
      final t = targetsFromV2(target: ['Pectoralis Major Clavicular Head'], secondary: ['Deltoid Anterior', 'Triceps Brachii']);
      expect(t.weights, {Muscle.upperChest: 1.0, Muscle.frontDelt: 0.3, Muscle.triceps: 0.3});
    });
  });

  group('mapping runs', () {
    test('high confidence is accepted, the rest queued with candidates; one search each', () async {
      final api = FakeEdb({
        'Barbell Bench Press': [hit('exr_bench', 'Barbell Bench Press'), hit('exr_db', 'Dumbbell Bench Press')],
        'Cable Crossover': [hit('exr_c1', 'Cable Standing Fly'), hit('exr_c2', 'Cable Middle Fly')],
      });
      final r = await repo.mapBatch([bench, fly], api, now: now, maxCalls: 2);
      expect(r.auto, [bench.id]);
      expect(r.queued, [fly.id]);
      expect(r.calls, 2);
      expect((await repo.get(bench.id))!.edbId, 'exr_bench');
      final q = (await repo.get(fly.id))!;
      expect(q.edbId, isNull);
      expect(q.candidates, contains('exr_c1'));
    });

    test('never spends more than the run budget; leftover calls check muscles of borderline matches', () async {
      final api = FakeEdb(
        {'Cable Crossover': [hit('exr_c1', 'Cable Crossover Fly')]},
        details: {'exr_c1': const EdbExercise(exerciseId: 'exr_c1', name: 'Cable Crossover Fly', targetMuscles: ['Pectoralis Major Sternal Head'])},
      );
      final infos = [fly, for (var i = 0; i < 5; i++) ex('X$i', 'Mystery $i', 'other', [])];
      final r = await repo.mapBatch(infos, api, now: now, maxCalls: 4);
      expect(r.calls, lessThanOrEqualTo(4));
      expect(api.calls.length, r.calls);
      expect(r.skipped, isNotEmpty);
    });

    test('confirmed mappings survive a reinstall through the asset export', () async {
      final api = FakeEdb({'Cable Crossover': [hit('exr_c1', 'Cable Standing Fly')]});
      await repo.mapBatch([fly], api, now: now);
      await repo.confirm(fly.id, 'exr_c1', now: now);
      final json = await repo.exportJson();

      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      final again = EdbMappingRepository(fresh);
      expect(await again.seedFromAsset(json, now: now), 1);
      final row = (await again.get(fly.id))!;
      expect(row.status, 'confirmed');
      expect(row.edbId, 'exr_c1');
      // Seeding never overwrites what the device already has.
      expect(await again.seedFromAsset(json, now: now), 0);
    });

    test('the bundled asset parses', () async {
      expect(await repo.seedFromAsset(File(EdbMappingRepository.assetPath).readAsStringSync(), now: now), greaterThanOrEqualTo(0));
    });
  });
}
