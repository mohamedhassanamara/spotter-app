// Load type and step of every exercise in my 5 routines, plus T-Bar Row / Pendulum Squat suggestions
// at the new steps → docs/LOAD_TYPES.md. Skipped unless LIFTOFF_CSV points at the export:
//
//   LIFTOFF_CSV=~/Desktop/DOCS/liftoff_workout_data.csv LIFTOFF_BW=108@2026-04-19,106@2026-10-11 \
//     flutter test test/tool/load_types_report_test.dart
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/load_types.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/load_kinds.dart';
import 'package:spotter/features/ranks/data/ranks_repository.dart';
import 'package:spotter/features/readiness/data/readiness_repository.dart';
import 'package:spotter/features/workout/data/history_repository.dart';
import 'package:spotter/features/workout/data/routine_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final path = Platform.environment['LIFTOFF_CSV']?.replaceFirst('~', Platform.environment['HOME'] ?? '~');

  test('load types of my routines → docs/LOAD_TYPES.md', () async {
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
    await service.commit(await service.preview(File(path!).readAsStringSync(), catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: now);
    final cat = await ExerciseRepository(db).watchCatalog().first;
    final history = await HistoryRepository(db).load(cat);
    final standards = await RanksRepository.loadStandards();
    final bwLoaded = RanksRepository.bodyweightLoadedIds(standards, cat);
    final bw = weighIns.last.$1;
    final routines = await RoutineRepository(db).watchRoutines().first;
    const gym = GymEquipment();

    final out = StringBuffer()
      ..writeln('# Load types and weight steps of my routines')
      ..writeln()
      ..writeln('Smallest plate ${formatKg(gym.smallestPlate)} kg: one-sided plate machines step ${formatKg(gym.smallestPlate)} kg, '
          'two-sided machines and barbells ${formatKg(gym.barbellStep)} kg (a pair), stacks and cables ${formatKg(gym.stack.step)} kg from '
          '${formatKg(gym.stack.start)} kg (default; per-exercise override in the logger menu → Weight steps…), dumbbells your list '
          '(${GymEquipment.describeDumbbells(gym.dumbbells)}). Every weight you have logged on an exercise also counts as available.')
      ..writeln()
      ..writeln('Wrong for your gym? Open the exercise in a workout → ⋮ → **Weight steps…** and pick stack / plate-loaded one side / both sides.')
      ..writeln()
      ..writeln('| Routine | Exercise | Library exercise | Dataset equipment | Load type | Step | Why |')
      ..writeln('|---|---|---|---|---|---|---|');
    for (final r in routines) {
      for (final re in r.exercises) {
        final info = cat[re.exerciseId]!;
        final assisted = isAssisted(info.id);
        final c = explainLoad(name: info.name, equipment: info.equipment, assisted: assisted);
        final step = gym.stepFor(info.id, c.type);
        out.writeln('| ${r.routine.name} | ${re.displayName ?? info.name} | ${info.name} | ${info.equipment ?? '–'} | ${c.type.label} | '
            '${step == null ? 'list' : '${formatKg(step)} kg'} | ${c.why} |');
      }
    }

    // T-Bar Row and Pendulum Squat: before (5 kg stack steps) vs now (2.5 kg), Green and Red, with today's history.
    out
      ..writeln()
      ..writeln('## T-Bar Row and Pendulum Squat today (history to 11 Oct)')
      ..writeln()
      ..writeln('"Before" = both treated as 5 kg stack machines; "now" = one-sided plate machines, 2.5 kg steps. Green = neutral readiness, Red = 30.')
      ..writeln()
      ..writeln('| Exercise | Reps | Last session | Before, Green | Now, Green | Before, Red | Now, Red | Now, Why |')
      ..writeln('|---|---|---|---|---|---|---|---|');
    for (final (name, exId, range, sets) in [
      ('Chest Supported T-Bar Row', 'Lying_T-Bar_Row', const RepRange(6, 8), 2),
      ('Pendulum Squat', 'sp_pendulum_squat', const RepRange(4, 6), 2),
    ]) {
      final info = cat[exId]!;
      final logs = history.logsForRange(info.id, range);
      final last = logs.isEmpty ? '–' : logs.last.workingSets.map((s) => '${formatKg(s.weight)}×${s.reps}').join(', ');
      Suggestion run(GymEquipment g, int score) => const SuggestionEngine().suggest(SuggestionInput(
            range: range,
            targetSets: sets,
            targetRir: 0,
            increment: 2.5,
            equipment: info.equipmentKind,
            history: logs,
            readiness: ExerciseReadiness(score: score, calibrating: false),
            now: now,
            bodyweight: bwLoaded.contains(info.id) ? bw : 0,
            rangeMatched: history.logsFor(info.id).isEmpty || history.hasLogsAtRange(info.id, range),
            grid: gridForExercise(g, history, info),
            compound: info.isCompound,
          ));
      final stackOverride = GymEquipment(typeOverrides: {info.id: LoadType.stack});
      String fmt(Suggestion s) => '${formatKg(s.weight)} kg × ${s.reps}, ${s.sets} sets';
      final nowGreen = run(gym, 60);
      out.writeln('| $name | $range | $last | ${fmt(run(stackOverride, 60))} | **${fmt(nowGreen)}** | ${fmt(run(stackOverride, 30))} | '
          '**${fmt(run(gym, 30))}** | ${nowGreen.why.where((w) => w.startsWith('Rule:') || w.startsWith('Weight:')).join(' ')} |');
    }
    File('docs/LOAD_TYPES.md').writeAsStringSync(out.toString());
    // ignore: avoid_print
    print(out);
  }, skip: path == null ? 'set LIFTOFF_CSV to regenerate docs/LOAD_TYPES.md' : null);
}
