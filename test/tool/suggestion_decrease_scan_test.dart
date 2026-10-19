// Scans every slot of my 5 routines, from my real Liftoff export, for suggestions that are LOWER than the last working
// weight, and writes docs/SUGGESTION_DECREASES.md (WHY each one is lower, and whether last time hit the top of the range).
// Skipped unless LIFTOFF_CSV points at the file:
//
//   LIFTOFF_CSV=~/Desktop/DOCS/liftoff_workout_data.csv LIFTOFF_BW=108@2026-04-19,106@2026-10-11 \
//     flutter test test/tool/suggestion_decrease_scan_test.dart
//
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/coach/domain/energy.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/load_kinds.dart';
import 'package:spotter/features/program/data/program_repository.dart';
import 'package:spotter/features/program/domain/program.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/readiness/data/readiness_repository.dart';
import 'package:spotter/features/recovery/domain/recovery.dart';
import 'package:spotter/features/workout/data/history_repository.dart';
import 'package:spotter/features/workout/data/routine_repository.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['LIFTOFF_CSV']?.replaceFirst('~', Platform.environment['HOME'] ?? '~');

  test('every suggestion below the last working weight, with its cause → docs/SUGGESTION_DECREASES.md', () async {
    final now = DateTime(2026, 10, 13, 9);
    final weighIns = [
      for (final part in (Platform.environment['LIFTOFF_BW'] ?? '106').split(','))
        part.contains('@') ? (double.parse(part.split('@')[0]), DateTime.parse(part.split('@')[1])) : (double.parse(part), now),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    for (final (kg, at) in weighIns) {
      await BodyWeightRepository(db).addManual(kg, at: at);
    }
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    final service = LiftoffImportService(db);
    await service.commit(await service.preview(File(path!).readAsStringSync(), catalog: catalog),
        catalog: catalog, settings: const SettingsModel(), now: now);

    final cat = await ExerciseRepository(db).watchCatalog().first;
    final history = await HistoryRepository(db).load(cat);
    final standards = await RanksRepository.loadStandards();
    final bwLoaded = RanksRepository.bodyweightLoadedIds(standards, cat);
    final bw = weighIns.last.$1;
    final program = await ProgramRepository.load();
    final routines = await RoutineRepository(db).watchRoutines().first;
    final energy = EnergyContext.compute(now: now, bodyweights: [for (final (kg, at) in weighIns) (at, kg)], nutrition: const []);
    final recovery = computeRecovery(history, now: now);
    const gym = GymEquipment.defaults;

    final rows = <(String, String, String, String, String, bool, String, String)>[];
    var total = 0;
    for (final r in routines) {
      for (final re in r.exercises) {
        final info = cat[re.exerciseId]!;
        final slots = decodeSlots(re.programSlots);
        final pres = prescribeSets(program: program, slotIds: slots, sets: re.targetSets);
        final groups = <List<SetPrescription>>[];
        for (final p in pres) {
          if (groups.isEmpty || groups.last.first.slotId != p.slotId) groups.add([]);
          groups.last.add(p);
        }
        for (final g in groups) {
          final range = g.first.repRange;
          final rir = g.first.targetRir ?? 0;
          final logs = history.logsForRange(info.id, range);
          final assisted = isAssisted(info.id);
          final body = bwLoaded.contains(info.id) ? bw : 0.0;
          final matched = history.logsFor(info.id).isEmpty || history.hasLogsAtRange(info.id, range);

          Suggestion after(int score) => const SuggestionEngine().suggest(SuggestionInput(
                range: range,
                targetSets: g.length,
                targetRir: rir,
                increment: Increments.defaults.of(info.equipmentKind),
                equipment: info.equipmentKind,
                history: logs,
                readiness: ExerciseReadiness(score: score, calibrating: false),
                now: now,
                bodyweight: body,
                assisted: assisted,
                rangeMatched: matched,
                grid: gridForExercise(gym, history, info),
                compound: info.isCompound,
                fatigued: [for (final m in fatiguedPrimaries(recovery, [info.targets])) m.label],
                energy: energy,
              ));


          final last = logs.where((l) => l.hasWorkingSets).lastOrNull;
          if (last == null) continue;
          final w = last.topWeight;
          final topHit = last.workingSets.every((x) => x.reps >= range.max);
          for (final (band, score) in const [('Green', 60), ('Red', 30)]) {
            final a = after(score);
            if (a.weight < w - 0.01) {
              rows.add((
                '${r.routine.name} · ${re.displayName ?? info.name}',
                '$range',
                '${formatKg(w)} kg × ${last.topSets.map((x) => x.reps).reduce((p, q) => p > q ? p : q)}${topHit ? ' (top of range)' : ''}',
                band,
                '${formatKg(a.weight)} kg × ${a.reps}',
                topHit,
                a.why.where((x) => x.startsWith('Rule:') || x.startsWith('Readiness:') || x.startsWith('Recovery:')).join(' ').replaceAll('|', '/'),
                "",
              ));
            }
          }
          total++;
        }
      }
    }
    final out = StringBuffer()
      ..writeln('# Suggestions lower than the last working weight')
      ..writeln()
      ..writeln('Generated by `test/tool/suggestion_decrease_scan_test.dart` from my Liftoff export (history up to 11 Oct; the CSV is not in the repo), as of 13 Oct 2026. '
          'Scanned $total program slots of my five routines at Green (60) and Red (30) readiness. '
          '**Sessions logged in the app since 11 Oct are not in this export.**')
      ..writeln()
      ..writeln('${rows.length} suggestion(s) below the last working weight, ${rows.where((r) => r.$6).length} of them after a session that hit the top of the range.')
      ..writeln()
      ..writeln('| Slot | Range | Last time | Readiness | Suggestion now | Last time at top of range? | Cause (rule lines) | Inline note |')
      ..writeln('|---|---|---|---|---|---|---|---|');
    for (final r in rows) {
      out.writeln('| ${r.$1} | ${r.$2} | ${r.$3} | ${r.$4} | **${r.$5}** | ${r.$6 ? 'YES' : 'no'} | ${r.$7} | ${r.$8} |');
    }
    File('docs/SUGGESTION_DECREASES.md').writeAsStringSync(out.toString());
    // ignore: avoid_print
    print('Wrote docs/SUGGESTION_DECREASES.md: ${rows.length} decreases in $total slots');
  }, skip: path == null ? 'set LIFTOFF_CSV to the Liftoff export to regenerate docs/SUGGESTION_DECREASES.md' : false, timeout: const Timeout(Duration(minutes: 5)));
}
