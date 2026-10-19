import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/data/coach_context.dart';
import 'package:spotter/features/coach/domain/energy.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';

/// The rule: hitting the top of the rep range at the prescribed effort NEVER leads to a lower weight (either +1 step, or the
/// same weight with reps extended past the range), whatever the exercise, its weights, the readiness or the recovery. And
/// every suggestion below the last working weight carries a stated reason.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 10, 19, 9);

  late Map<String, ExerciseInfo> catalog;
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await bootstrapDatabase(db);
    catalog = await ExerciseRepository(db).watchCatalog().first;
    await db.close();
  });

  ExerciseSessionLog session(DateTime day, double weight, int reps, double rpe, {int sets = 3}) => ExerciseSessionLog(
        sessionId: day.millisecondsSinceEpoch,
        date: day,
        suggestionKind: SuggestionKind.none,
        sets: [for (var i = 0; i < sets; i++) LoggedSet(weight: weight, reps: reps, rpe: rpe)],
      );

  test('top of range at the prescribed effort: next weight ≥ last weight, for every exercise in the library', () {
    expect(catalog.length, greaterThan(1000));
    const ranges = [RepRange(4, 6), RepRange(6, 8), RepRange(10, 12), RepRange(20, 20)];
    const bands = [60, 45, 30]; // Green, Yellow, Red
    var cases = 0;
    for (final info in catalog.values) {
      final grid = const GymEquipment().gridFor(exerciseId: info.id, kind: info.equipmentKind, type: loadTypeOf(info));
      final values = grid.values.where((v) => v > 0).toList();
      if (values.length < 3) continue;
      final picks = {values[1], values[values.length ~/ 2], values[values.length - 2]};
      for (final w in picks) {
        for (final range in ranges) {
          for (final rir in const [0, 2]) {
            for (final score in bands) {
              for (final fatigued in const [false, true]) {
                for (final deficit in const [false, true]) {
                  final s = const SuggestionEngine().suggest(SuggestionInput(
                    range: range,
                    targetSets: 3,
                    targetRir: rir,
                    increment: 2.5,
                    equipment: info.equipmentKind,
                    history: [
                      session(now.subtract(const Duration(days: 14)), w, range.max - 1, 10.0 - rir),
                      session(now.subtract(const Duration(days: 7)), w, range.max, 10.0 - rir),
                    ],
                    readiness: ExerciseReadiness(score: score, calibrating: false),
                    now: now,
                    grid: grid,
                    compound: info.isCompound,
                    fatigued: fatigued ? const ['Chest'] : const [],
                    energy: deficit ? const EnergyContext(avg7: 100, slopePerWeek: -0.5) : EnergyContext.none,
                  ));
                  cases++;
                  if (s.weight < w - 0.01) {
                    fail('${info.name} (${info.id}): top of $range at RIR $rir with $w kg → ${s.weight} kg, score $score, '
                        'fatigued $fatigued, deficit $deficit\n${s.why.join('\n')}');
                  }
                  expect(s.downNote, isNull);
                  // Either one step up, or the same weight with the reps pushed past the range (a jump over 10 % waits).
                  final next = grid.next(w);
                  expect(s.weight, anyOf(w, next ?? w), reason: '${info.id}');
                }
              }
            }
          }
        }
      }
    }
    expect(cases, greaterThan(100000));
  });

  test('any suggestion below the last working weight has its reason in the inline note (random histories, 20,000)', () {
    final rng = math.Random(11);
    final grids = [
      for (final info in catalog.values.take(400)) (info, const GymEquipment().gridFor(exerciseId: info.id, kind: info.equipmentKind, type: loadTypeOf(info))),
    ];
    var decreases = 0;
    for (var i = 0; i < 20000; i++) {
      final (info, grid) = grids[rng.nextInt(grids.length)];
      final values = grid.values.where((v) => v > 0).toList();
      if (values.length < 2) continue;
      final sessions = 1 + rng.nextInt(5);
      final range = [const RepRange(4, 6), const RepRange(6, 8), const RepRange(10, 12), const RepRange(20, 20)][rng.nextInt(4)];
      final history = [
        for (var k = 0; k < sessions; k++)
          ExerciseSessionLog(
            sessionId: k,
            date: now.subtract(Duration(days: 7 * (sessions - k))),
            suggestionKind: rng.nextInt(8) == 0 ? SuggestionKind.calibration : SuggestionKind.none,
            sets: [
              for (var j = 0; j < 1 + rng.nextInt(3); j++)
                LoggedSet(weight: values[rng.nextInt(values.length)], reps: 2 + rng.nextInt(range.max + 5), rpe: 6.0 + rng.nextInt(5)),
            ],
          ),
      ];
      final matched = rng.nextInt(5) != 0; // false: no sets at this rep range yet, so there is no "last time" for the slot
      final freeze = rng.nextInt(10) == 0 ? FreezeState(until: now.add(const Duration(days: 3)), baseWeight: values[rng.nextInt(values.length)]) : null;
      final s = const SuggestionEngine().suggest(SuggestionInput(
        range: range,
        targetSets: 3,
        targetRir: rng.nextInt(3),
        increment: 2.5,
        equipment: info.equipmentKind,
        history: history,
        readiness: ExerciseReadiness(score: [60, 45, 30][rng.nextInt(3)], calibrating: false),
        now: now,
        grid: grid,
        compound: rng.nextBool(),
        freeze: freeze,
        rangeMatched: matched,
        energy: rng.nextBool() ? const EnergyContext(avg7: 100, slopePerWeek: -0.5) : EnergyContext.none,
        fatigued: rng.nextBool() ? const ['Chest'] : const [],
      ));
      final last = history.last.topWeight;
      if (s.weight < last - 0.01 && matched) {
        decreases++;
        expect(s.downNote, isNotNull, reason: 'case $i: ${info.id} $last → ${s.weight}');
        expect(s.downNote, startsWith('↓ from '));
      } else {
        expect(s.downNote, isNull, reason: 'case $i: no decrease for the slot, no note');
      }
    }
    expect(decreases, greaterThan(0), reason: 'the generator must produce some decreases to be a test (ego freezes, re-anchors)');
  });

  test('the inline note names the rule: ego freeze, no recent sets at the range, calibration', () {
    final grid = const GymEquipment().gridFor(exerciseId: 'db', kind: catalog.values.firstWhere((e) => e.equipment == 'dumbbell').equipmentKind);
    final frozen = const SuggestionEngine().suggest(SuggestionInput(
      range: const RepRange(6, 8),
      targetSets: 3,
      targetRir: 0,
      increment: 2.5,
      equipment: catalog.values.firstWhere((e) => e.equipment == 'dumbbell').equipmentKind,
      history: [session(now.subtract(const Duration(days: 7)), 20, 8, 10)],
      readiness: ExerciseReadiness.neutral,
      now: now,
      grid: grid,
      freeze: FreezeState(until: now.add(const Duration(days: 4)), baseWeight: 20),
    ));
    expect(frozen.downNote, contains('↓ from 20 kg: ego flag'));
    expect(frozen.downNote, contains('4 more day(s)'));
  });
}
