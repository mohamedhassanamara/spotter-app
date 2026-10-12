// One-off: maps every exercise in my routines and Liftoff history to ExerciseDB V2 with REAL API calls
// (at most 150, counted against the monthly plan) and writes assets/edb_v2_map.json. Skipped unless
// EDB_LIVE=1; the key is read from the git-ignored config/secrets.json and never printed.
//
//   EDB_LIVE=1 EDB_REPORT=/tmp/edb_queue.md flutter test test/tool/edb_initial_mapping_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/import/domain/liftoff_mapping.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/tutorials/data/edb_v2/edb_client.dart';
import 'package:spotter/features/tutorials/data/edb_v2/edb_mapping_repository.dart';
import 'package:spotter/features/tutorials/domain/edb_v2_mapping.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final live = Platform.environment['EDB_LIVE'] == '1';

  test('initial ExerciseDB V2 mapping (live, ≤ 150 calls)', () async {
    // flutter_test answers every HTTP request with a fake 400; this tool needs the real network.
    HttpOverrides.global = null;
    final key = (jsonDecode(File('config/secrets.json').readAsStringSync()) as Map<String, dynamic>)['EDB_RAPIDAPI_KEY'] as String;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    final store = EdbBudgetStore(db);
    final client = http.Client();
    addTearDown(client.close);
    final api = EdbV2Client(client: client, store: store, apiKey: key);

    // The Liftoff-only custom exercises, as the import would create them.
    final nameMap = LiftoffNameMap.parse(File('assets/liftoff_name_map.json').readAsStringSync());
    final customs = {
      for (final e in nameMap.customs.entries)
        liftoffCustomId(e.key): ExerciseInfo(
          id: liftoffCustomId(e.key),
          name: e.value.name,
          primaryMuscles: e.value.primaryMuscles,
          secondaryMuscles: e.value.secondaryMuscles,
          equipment: e.value.equipment,
          level: null,
          mechanic: e.value.compound ? 'compound' : 'isolation',
          category: 'strength',
          instructions: const [],
          images: const [],
          isCustom: true,
          isFavorite: false,
          notes: null,
        ),
    };
    final all = {...catalog, ...customs};
    // Routine exercises first, then the rest of the Liftoff history (the hand-authored muscle table
    // covers exactly these 111 exercises).
    final routines = jsonDecode(File('assets/programs/my_routines.json').readAsStringSync()) as Map<String, dynamic>;
    final routineIds = [
      for (final r in (routines['routines'] as List<dynamic>).cast<Map<String, dynamic>>())
        for (final e in (r['exercises'] as List<dynamic>).cast<Map<String, dynamic>>()) e['exercise_id'] as String,
    ];
    final mine = ((jsonDecode(File('assets/exercise_muscles.json').readAsStringSync()) as Map<String, dynamic>)['exercises'] as Map<String, dynamic>).keys;
    final ordered = [...{...routineIds, ...mine}];
    final infos = [for (final id in ordered) ?all[id]];
    expect(infos.length, ordered.length, reason: 'every exercise resolves');

    final repo = EdbMappingRepository(db);
    final run = await repo.mapBatch(infos, api, now: DateTime.now(), maxCalls: 150);
    File(EdbMappingRepository.assetPath).writeAsStringSync(await repo.exportJson());

    final budget = await store.load(DateTime.now());
    final rows = await db.select(db.edbV2Maps).get();
    final out = StringBuffer()
      ..writeln('# ExerciseDB V2 initial mapping')
      ..writeln()
      ..writeln('Calls used by this run: ${run.calls} (cap 150). RapidAPI usage this month after the run: '
          '${budget.used}${budget.fromHeaders ? ' (from RapidAPI headers)' : ' (local count)'}.')
      ..writeln('Auto-accepted ${run.auto.length} · queued ${run.queued.length} · no candidates ${run.none.length} · '
          'not attempted ${run.skipped.length}.')
      ..writeln()
      ..writeln('## Low-confidence queue')
      ..writeln();
    for (final r in rows.where((r) => r.status == 'queued')) {
      final c = (jsonDecode(r.candidates) as List<dynamic>).cast<Map<String, dynamic>>();
      out.writeln('- **${all[r.exerciseId]?.name}** (`${r.exerciseId}`), searched "${r.query}": '
          '${c.take(3).map((x) => '${x['name']} ${((x['score'] as num) * 100).round()}%').join(' · ')}');
    }
    out
      ..writeln()
      ..writeln('## No candidates')
      ..writeln();
    for (final r in rows.where((r) => r.status == 'none')) {
      out.writeln('- ${all[r.exerciseId]?.name} (searched "${r.query}")');
    }
    out
      ..writeln()
      ..writeln('## Auto-accepted')
      ..writeln();
    for (final id in run.auto) {
      final r = rows.firstWhere((x) => x.exerciseId == id);
      out.writeln('- ${all[id]?.name} → `${r.edbId}` (${(r.confidence * 100).round()}%)');
    }
    final report = Platform.environment['EDB_REPORT'];
    if (report != null) File(report).writeAsStringSync(out.toString());
    // ignore: avoid_print
    print('EDB mapping: ${run.calls} calls · auto ${run.auto.length} · queued ${run.queued.length} · none ${run.none.length} · skipped ${run.skipped.length}');
    expect(run.calls, lessThanOrEqualTo(150));
    expect(muscleForV2('Pectoralis Major Sternal Head'), isNotNull);
  }, skip: live ? false : 'live API run; set EDB_LIVE=1', timeout: const Timeout(Duration(minutes: 10)));
}
