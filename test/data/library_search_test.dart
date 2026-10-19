import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/exercise_aliases.dart';
import 'package:spotter/features/library/domain/exercise_filter.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final routines = _json('assets/programs/my_routines.json');
  final aliases = buildAliases(
    myRoutines: routines,
    canonicalProgram: _json('assets/programs/min_max_canonical.json'),
    liftoffMap: _json('assets/liftoff_name_map.json'),
  );

  test('search words: hyphens, punctuation, spacing and plurals do not matter', () {
    expect(searchTokens('High-to-Low Cable Fly'), ['high', 'to', 'low', 'cable', 'fly']);
    for (final q in ['high to low', 'high-to-low', 'hightolow', 'HIGH-TO', 'high to', 'cable flyes', 'flye']) {
      expect(searchMatches('High-to-Low Cable Fly Flye', q), isTrue, reason: q);
    }
    expect(searchMatches('Cable Crossover', 'high-to'), isFalse);
    expect(searchTokens('Lunges'), ['lunge']);
    expect(searchTokens('Presses'), ['press']);
    expect(searchTokens('Flyes'), ['fly']);
  });

  test('aliases: my names, the program names and substitutions, and the Liftoff names all lead to the library exercise', () {
    expect(aliases['Cable_Crossover'], containsAll(['High-to-Low Cable Fly', 'Cable Flye']));
    expect(aliases['Leg_Press'], contains('Sled Leg Press'), reason: 'a Liftoff name');
    expect(aliases['Leverage_Chest_Press'], contains('Machine Chest Press'), reason: 'the program name');
    // The program's substitutions for a slot belong to the exercise that fills it.
    final canonical = _json('assets/programs/min_max_canonical.json');
    final slot = (((canonical['days'] as List).first as Map<String, dynamic>)['slots'] as List).first as Map<String, dynamic>;
    final subs = (slot['substitutions'] as List).map((s) => s is Map ? (s['name'] ?? s['exercise']) as String : s as String);
    expect(aliases['Leverage_Chest_Press'], containsAll(subs));
  });

  test('every exercise in my routines is in the library, and any 4+ letter fragment of its names finds it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    var checked = 0;
    for (final r in (routines['routines'] as List)) {
      for (final e in ((r as Map)['exercises'] as List).cast<Map<String, dynamic>>()) {
        final id = e['exercise_id'] as String;
        final info = catalog[id];
        expect(info, isNotNull, reason: '${e['name']} ($id) must be in the library');
        for (final name in {info!.name, e['name'] as String, e['program_exercise'] as String}) {
          for (var len = 4; len <= name.length; len++) {
            for (var i = 0; i + len <= name.length; i++) {
              final frag = name.substring(i, i + len).trim();
              if (frag.length < 4 && !RegExp(r'[a-zA-Z]{1}').hasMatch(frag)) continue;
              expect(ExerciseFilter(query: frag).matches(info, aliases: aliases), isTrue, reason: '"$frag" (of "$name") must find ${info.name}');
              checked++;
            }
          }
        }
      }
    }
    expect(checked, greaterThan(2000));
  });

  test('the library search through the filter: "high-to" finds Cable Crossover and says why', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    const f = ExerciseFilter(query: 'high-to');
    final found = f.apply(catalog.values, aliases: aliases);
    expect(found.map((e) => e.id), contains('Cable_Crossover'));
    expect(f.matchedAlias(catalog['Cable_Crossover']!, aliases), 'High-to-Low Cable Fly');
    expect(const ExerciseFilter(query: 'cable cross').matchedAlias(catalog['Cable_Crossover']!, aliases), isNull, reason: 'its own name matched');
    expect(const ExerciseFilter(query: 'high-to').apply(catalog.values).map((e) => e.id), isNot(contains('Cable_Crossover')), reason: 'without aliases it is not found (the bug)');
  });
}
