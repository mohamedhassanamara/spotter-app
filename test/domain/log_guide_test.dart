import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/load_types.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/load_kinds.dart';
import 'package:spotter/features/library/domain/log_guide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  LogGuide g(String name, String? eq, {bool assisted = false, LoadType? o}) => logGuideFor(name: name, equipment: eq, assisted: assisted, override: o);

  test('each load type has its rule', () {
    expect(g('Dumbbell Bench Press', 'dumbbell').headline, 'Log the weight of ONE dumbbell');
    expect(g('Leg Press', 'machine').headline, 'Log total plates on both sides');
    expect(g('T-Bar Row', 'machine').headline, 'Log total plates on the sleeve');
    expect(g('Lat Pulldown', 'cable').headline, 'Log the stack weight');
    expect(g('Assisted Dip (Machine)', 'machine', assisted: true).headline, 'Log the assistance as negative');
    expect(g('Single-Arm Cable Curl', 'cable').headline, 'Log the weight for one side');
    expect(g('One-Arm Dumbbell Row', 'dumbbell').headline, 'Log the weight of ONE dumbbell');
    expect(g('Barbell Squat', 'barbell').headline, 'Log the total weight on the bar');
    expect(g('Pull-up', 'body only').headline, 'Log only the weight you add');
  });

  test('every rule says whether the bar, sled or carriage is included', () {
    expect(g('Barbell Squat', 'barbell').includes, contains('bar (20 kg) is included'));
    expect(g('Leg Press', 'machine').includes, contains('sled'));
    expect(g('Leg Press', 'machine').includes, contains('not counted'));
    expect(g('T-Bar Row', 'machine').includes, contains('not counted'));
    expect(g('Lat Pulldown', 'cable').includes, contains('Just the stack'));
  });

  test('the load type you chose in the logger wins over the classification', () {
    expect(g('Chest Press', 'machine').headline, 'Log the stack weight');
    expect(g('Chest Press', 'machine', o: LoadType.plateBothSides).headline, 'Log total plates on both sides');
  });

  test('every exercise in the library, and every one in my routines, has a complete rule', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    var other = 0;
    for (final e in catalog.values) {
      final guide = logGuideFor(name: e.name, equipment: e.equipment, assisted: isAssisted(e.id), bodyweightLoaded: extraBodyweightExerciseIds.contains(e.id));
      expect(guide.headline, isNotEmpty, reason: e.name);
      expect(guide.detail, isNotEmpty, reason: e.name);
      expect(guide.includes, isNotEmpty, reason: e.name);
      if (guide.type == LoadType.other) other++;
    }
    expect(other, lessThan(catalog.length ~/ 3), reason: 'most exercises are classified, not the "no equipment" fallback');
    final routines = jsonDecode(File('assets/programs/my_routines.json').readAsStringSync()) as Map<String, dynamic>;
    for (final r in (routines['routines'] as List)) {
      for (final e in ((r as Map)['exercises'] as List).cast<Map<String, dynamic>>()) {
        final info = catalog[e['exercise_id']]!;
        expect(logGuideFor(name: info.name, equipment: info.equipment, assisted: isAssisted(info.id), bodyweightLoaded: extraBodyweightExerciseIds.contains(info.id)).type, isNot(LoadType.other),
            reason: '${info.name} needs a defined load type');
      }
    }
  });

  test('equipment tiles: what the exercise needs', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    List<String> tiles(String id) => equipmentTiles(catalog[id]!).map((t) => t.label).toList();
    expect(tiles('Cable_Crossover'), ['Cable']);
    expect(tiles('Smith_Machine_Overhead_Shoulder_Press'), contains('Smith machine'));
    expect(tiles('Barbell_Bench_Press_-_Medium_Grip'), containsAll(['Barbell', 'Bench']));
    expect(tiles('Preacher_Hammer_Dumbbell_Curl'), containsAll(['Dumbbells', 'Preacher bench']));
  });
}
