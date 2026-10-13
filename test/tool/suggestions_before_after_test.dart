// Before/after suggestions for every exercise in my 5 routines, from my real Liftoff export, and
// writes docs/SUGGESTIONS_BEFORE_AFTER.md. Skipped unless LIFTOFF_CSV points at the file:
//
//   LIFTOFF_CSV=~/Desktop/DOCS/liftoff_workout_data.csv LIFTOFF_BW=108@2026-04-19,106@2026-10-11 \
//     flutter test test/tool/suggestions_before_after_test.dart
//
// "Before" is the engine as it was before Fix 6 (test/tool/legacy/suggestion_engine_v1.dart), with
// its old 2.5 / 2 kg increments. "After" is today's engine with the default gym equipment.
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/history.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/coach/domain/energy.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';
import 'package:spotter/features/library/domain/load_kinds.dart';
import 'package:spotter/features/program/data/program_repository.dart';
import 'package:spotter/features/program/domain/program.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/readiness/data/readiness_repository.dart';
import 'package:spotter/features/recovery/domain/recovery.dart';
import 'package:spotter/features/workout/data/history_repository.dart';
import 'package:spotter/features/workout/data/routine_repository.dart';

import 'legacy/suggestion_engine_v1.dart' as legacy;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['LIFTOFF_CSV']?.replaceFirst('~', Platform.environment['HOME'] ?? '~');

  test('before/after suggestions for my routines → docs/SUGGESTIONS_BEFORE_AFTER.md', () async {
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

    String fmt(double w, int reps, int sets, bool assisted) =>
        '${w < 0 ? '${formatKg(-w)} kg assist' : (w == 0 ? 'BW' : '${formatKg(w)} kg')} × $reps${sets > 1 ? ', $sets sets' : ''}';

    final rows = <String>[];
    var changed = 0;
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

          legacy.Suggestion before(int score) => const legacy.LegacySuggestionEngine().suggest(legacy.SuggestionInput(
                range: range,
                targetSets: g.length,
                targetRir: rir,
                increment: Increments.defaults.of(info.equipmentKind),
                equipment: info.equipmentKind,
                history: logs,
                readiness: legacy.ExerciseReadiness(score: score, calibrating: false),
                now: now,
                bodyweight: body,
                assisted: assisted,
                rangeMatched: matched,
              ));
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

          final bg = before(60), ag = after(60), br = before(30), ar = after(30);
          final diff = bg.weight != ag.weight || bg.reps != ag.reps || br.weight != ar.weight;
          if (diff) changed++;
          final reason = !diff
              ? ''
              : [
                  ...ag.why.where((w) => w.startsWith('Rule:') || w.startsWith('Weight:') && w.contains('isn')),
                  if (br.weight != ar.weight) ...ar.why.where((w) => w.startsWith('Readiness:')),
                ].map((w) => w.replaceAll('|', '/')).join(' ');
          rows.add('| ${r.routine.name} | ${re.displayName ?? info.name} | $range | ${fmt(bg.weight, bg.reps, bg.sets, assisted)} | '
              '**${fmt(ag.weight, ag.reps, ag.sets, assisted)}** | ${fmt(br.weight, br.reps, br.sets, assisted)} | '
              '**${fmt(ar.weight, ar.reps, ar.sets, assisted)}** | ${diff ? reason : 'same'} |');
        }
      }
    }

    final out = StringBuffer()
      ..writeln('# Suggestions before / after Fix 6')
      ..writeln()
      ..writeln('Generated by `test/tool/suggestions_before_after_test.dart` from my Liftoff export (history up to 11 Oct; the CSV '
          'is not in the repo), as of ${now.day} Oct ${now.year}. One row per program slot of each routine exercise. '
          '"Before" = the engine before Fix 6 with the old increments; "after" = today\'s engine with the default gym '
          'equipment (dumbbells 2.5–50 kg by 2.5, barbell plates 2.25 kg a side, stacks 5 + 5 kg, plus any weight logged on the '
          'exercise). Green = neutral readiness (60), Red = 30. Bodyweight trend from the weigh-ins below; no nutrition data in this run.')
      ..writeln()
      ..writeln('Bodyweight: ${energy.describe().replaceAll('\n', ' · ')}')
      ..writeln()
      ..writeln('**Sessions logged in the app since 11 Oct are not in this export**, so check these against the logger\'s "why" on the day.')
      ..writeln()
      ..writeln('$changed of ${rows.length} slots change.')
      ..writeln()
      ..writeln('| Routine | Exercise | Reps | Before, Green | After, Green | Before, Red | After, Red | Why it changed |')
      ..writeln('|---|---|---|---|---|---|---|---|');
    rows.forEach(out.writeln);
    File('docs/SUGGESTIONS_BEFORE_AFTER.md').writeAsStringSync(out.toString());
    // ignore: avoid_print
    print(out);
  }, skip: path == null ? 'set LIFTOFF_CSV to the Liftoff export to regenerate docs/SUGGESTIONS_BEFORE_AFTER.md' : null);
}

// Referenced so the analyzer keeps the imports honest when skipped.
// ignore: unused_element
void _unused(TrainingHistory h, ExerciseInfo i) {}
