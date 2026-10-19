import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/domain/energy.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';

import '../tool/legacy/suggestion_engine_v1.dart' as legacy;

final now = DateTime(2026, 10, 13, 18);

ExerciseSessionLog log(DateTime day, List<(double, int)> sets, {double? rpe = 10, SuggestionKind kind = SuggestionKind.none}) => ExerciseSessionLog(
      sessionId: day.millisecondsSinceEpoch,
      date: day,
      suggestionKind: kind,
      sets: [for (final s in sets) LoggedSet(weight: s.$1, reps: s.$2, rpe: rpe)],
    );

const green = ExerciseReadiness(score: 70, calibrating: false);
const yellow = ExerciseReadiness(score: 45, calibrating: false);
const red = ExerciseReadiness(score: 30, calibrating: false);

final dumbbells = GymEquipment.defaults.gridFor(exerciseId: 'db', kind: EquipmentKind.dumbbell);

Suggestion suggest(
  List<ExerciseSessionLog> h, {
  RepRange range = const RepRange(10, 12),
  ExerciseReadiness readiness = green,
  WeightGrid? grid,
  bool compound = false,
  List<String> fatigued = const [],
  EnergyContext energy = EnergyContext.none,
  FormReset? reset,
  FreezeState? freeze,
  int rir = 0,
  EquipmentKind eq = EquipmentKind.dumbbell,
}) =>
    const SuggestionEngine().suggest(SuggestionInput(
      range: range,
      targetSets: 3,
      targetRir: rir,
      increment: 2.5,
      equipment: eq,
      history: h,
      readiness: readiness,
      now: now,
      grid: grid ?? dumbbells,
      compound: compound,
      fatigued: fatigued,
      energy: energy,
      formReset: reset,
      freeze: freeze,
    ));

/// My Dumbbell Incline Y Raise (10–12, RIR 0) from the Liftoff import, the three sessions before
/// "today": best 10 kg × 13 earlier; 29 Sep 10 × 10, 10 × 10, 7.5 × 15; 6 Oct (deliberate drop)
/// 7.5 × 10, 7.5 × 12, 5 × 15. Logged without RPE (imported sets count as to failure).
final yRaise = [
  log(DateTime(2026, 9, 15, 11), [(10, 10), (10, 13), (10, 6)], rpe: null),
  log(DateTime(2026, 9, 22, 11), [(10, 12), (10, 12), (10, 8)], rpe: null),
  log(DateTime(2026, 9, 29, 11), [(10, 10), (10, 10), (7.5, 15)], rpe: null),
  log(DateTime(2026, 10, 6, 11), [(7.5, 10), (7.5, 12), (5, 15)], rpe: null),
];

void main() {
  group('Y Raise regression (real history)', () {
    test('before: the old engine suggested 6 kg on a Red day (a weight that doesn\'t exist)', () {
      final old = const legacy.LegacySuggestionEngine().suggest(legacy.SuggestionInput(
        range: const RepRange(10, 12),
        targetSets: 3,
        targetRir: 0,
        increment: 2,
        equipment: EquipmentKind.dumbbell,
        history: yRaise,
        readiness: const legacy.ExerciseReadiness(score: 30, calibrating: false),
        now: now,
      ));
      expect(old.weight, 6);
    });

    for (final (name, r) in [('Green', green), ('Yellow', yellow), ('Red', red)]) {
      test('after: 7.5 kg on a $name day, all 3 sets, with the reason', () {
        final s = suggest(yRaise, readiness: r);
        expect(s.weight, 7.5);
        expect(s.sets, 3, reason: 'the routine\'s sets, always');
        expect(dumbbells.contains(s.weight), isTrue);
        expect(s.why.first, startsWith('Base: last session (6/10)'));
        expect(s.why.any((w) => w.startsWith('Rule: within 10–12')), isTrue);
        expect(s.why.last, 'Weight: 7.5 kg exists in your gym.');
        if (r == green) {
          expect(s.reps, 11, reason: 'beat last time\'s reps');
        } else {
          expect(s.reps, 12, reason: 'repeat last session: 7.5 kg × 12');
          expect(s.why.any((w) => w.contains('repeat last session (7.5 kg × 12), all 3 sets')), isTrue);
        }
      });
    }

    test('the deliberate drop to 7.5 kg at the top of the range offers a form reset', () {
      final s = suggest(yRaise);
      expect(s.formResetHint, 7.5);
      expect(s.why.any((w) => w.startsWith('Form reset?')), isTrue);
    });
  });

  group('only weights that exist', () {
    final grids = {
      'dumbbell': (dumbbells, EquipmentKind.dumbbell),
      'barbell': (GymEquipment.defaults.gridFor(exerciseId: 'bb', kind: EquipmentKind.barbell), EquipmentKind.barbell),
      'machine': (GymEquipment.defaults.gridFor(exerciseId: 'm', kind: EquipmentKind.machineCable), EquipmentKind.machineCable),
      'custom stack': (const GymEquipment(stack: StackSpec(start: 2, step: 7)).gridFor(exerciseId: 'c', kind: EquipmentKind.machineCable), EquipmentKind.machineCable),
    };
    test('no suggestion is ever off-grid (2,000 random histories × readiness × recovery × nutrition)', () {
      final rng = math.Random(7);
      final readiness = [green, yellow, red];
      for (var i = 0; i < 2000; i++) {
        final (grid, eq) = grids.values.elementAt(i % grids.length);
        final sessions = 1 + rng.nextInt(5);
        final h = [
          for (var k = 0; k < sessions; k++)
            log(now.subtract(Duration(days: 7 * (sessions - k))), [
              for (var j = 0; j < 3; j++) (grid.values[rng.nextInt(math.min(grid.values.length, 30))], 3 + rng.nextInt(14)),
            ], rpe: 7 + rng.nextInt(4).toDouble()),
        ];
        final range = [const RepRange(4, 6), const RepRange(6, 8), const RepRange(10, 12), const RepRange(20, 20)][rng.nextInt(4)];
        final s = suggest(
          h,
          range: range,
          readiness: readiness[rng.nextInt(3)],
          grid: grid,
          eq: eq,
          compound: rng.nextBool(),
          fatigued: rng.nextBool() ? const ['Chest'] : const [],
          energy: rng.nextBool() ? const EnergyContext(avg7: 100, slopePerWeek: -0.5) : EnergyContext.none,
        );
        expect(grid.contains(s.weight), isTrue, reason: 'case $i: ${s.weight} not in the grid (${s.why.join(' | ')})');
      }
    });

    test('the lighter OPTION after three bad sessions snaps down to the next lighter weight you have', () {
      // 10 kg below the range three times → −5 % = 9.5 → the next lighter dumbbell, 7.5, offered but not applied.
      final h = [for (var d = 21; d >= 7; d -= 7) log(now.subtract(Duration(days: d)), [(10, 7), (10, 6)])];
      final s = suggest(h, range: const RepRange(8, 10));
      expect(s.weight, 10, reason: 'never applied');
      expect(s.lighterOption, 7.5);
      expect(dumbbells.contains(s.lighterOption!), isTrue);
    });

    test('weights you have logged exist even if the settings don\'t list them (a 72 kg stack position)', () {
      final grid = GymEquipment.defaults.gridFor(exerciseId: 'p', kind: EquipmentKind.machineCable, logged: [72]);
      final s = suggest([log(now.subtract(const Duration(days: 7)), [(72, 5), (72, 4)])], range: const RepRange(4, 6), grid: grid, eq: EquipmentKind.machineCable);
      expect(s.weight, 72);
    });
  });

  group('no silent decreases, no drop spirals', () {
    test('Yellow / Red never cut an isolation below last session, and never take a set', () {
      final h = [log(now.subtract(const Duration(days: 7)), [(12.5, 11), (12.5, 10)])];
      expect(suggest(h, readiness: yellow).weight, 12.5);
      final r = suggest(h, readiness: red);
      expect(r.weight, 12.5);
      expect(r.reps, 11);
      expect(r.sets, 3);
    });

    test('Red on a compound: repeat, never a step down', () {
      final grid = GymEquipment.defaults.gridFor(exerciseId: 'bb', kind: EquipmentKind.barbell);
      final h = [log(now.subtract(const Duration(days: 7)), [(65, 6), (65, 5)])];
      final s = suggest(h, range: const RepRange(4, 6), readiness: red, grid: grid, compound: true, eq: EquipmentKind.barbell);
      expect(s.weight, 65);
      expect(s.downNote, isNull);
    });

    test('falling short three sessions in a row never lowers the weight by itself', () {
      final h = [
        log(DateTime(2026, 9, 22), [(15, 10), (15, 10)]),
        log(DateTime(2026, 9, 29), [(12.5, 9), (12.5, 8)]),
        log(DateTime(2026, 10, 6), [(10, 9), (10, 8)]),
      ];
      final s = suggest(h);
      expect(s.weight, 10);
      expect(s.downNote, isNull);
    });

    test('...but an ego flag (freeze active) does lower it, and says so visibly', () {
      final h = [
        log(DateTime(2026, 9, 22), [(15, 10), (15, 10)]),
        log(DateTime(2026, 9, 29), [(12.5, 9), (12.5, 8)]),
        log(DateTime(2026, 10, 6), [(10, 9), (10, 8)]),
      ];
      final s = suggest(h, freeze: FreezeState(until: now.add(const Duration(days: 3)), baseWeight: 10));
      expect(s.weight, lessThan(10));
      expect(s.downNote, startsWith('↓ from 10 kg: ego flag'));
    });

    test('big jump (7.5 → 10 kg dumbbells = +33 %): extend reps past the range first, then jump', () {
      final atTop = suggest([log(now.subtract(const Duration(days: 7)), [(7.5, 12), (7.5, 12)])]);
      expect(atTop.weight, 7.5);
      expect(atTop.reps, 13);
      expect(atTop.why.any((w) => w.contains('+33 %') && w.contains('extend to 14–15 reps')), isTrue);
      final extended = suggest([log(now.subtract(const Duration(days: 7)), [(7.5, 14), (7.5, 14)])]);
      expect(extended.weight, 10);
      expect(extended.kind, SuggestionKind.increase);
    });

    test('small jumps (a barbell +2 %) go up at the top of the range as before', () {
      final grid = GymEquipment.defaults.gridFor(exerciseId: 'bb', kind: EquipmentKind.barbell);
      final s = suggest([log(now.subtract(const Duration(days: 7)), [(110, 6), (110, 6)])], range: const RepRange(4, 6), grid: grid, eq: EquipmentKind.barbell);
      expect(s.weight, grid.next(110));
    });

    test('below the range, whenever: hold the weight (also right after a jump, and from the third session on)', () {
      final h = [
        log(DateTime(2026, 9, 29), [(7.5, 14), (7.5, 14)]),
        log(DateTime(2026, 10, 6), [(10, 9), (10, 8)]),
      ];
      expect(suggest(h).weight, 10);
      final third = suggest([...h, log(DateTime(2026, 10, 9), [(10, 9), (10, 8)]), log(DateTime(2026, 10, 12), [(10, 9), (10, 8)])]);
      expect(third.weight, 10, reason: 'still held; at most a lighter option');
      expect(third.downNote, isNull);
    });

    test('form reset: progression restarts from the reset weight and old heavier sets don\'t trigger reductions', () {
      final reset = FormReset(weight: 7.5, at: DateTime(2026, 10, 6));
      final s = suggest(yRaise, reset: reset);
      expect(s.weight, 7.5);
      expect(s.formResetHint, isNull, reason: 'already reset');
      expect(s.why.first, contains('since your form reset on 6/10'));
      final fresh = suggest(yRaise.take(3).toList(), reset: FormReset(weight: 7.5, at: now));
      expect(fresh.weight, 7.5);
      expect(fresh.reps, 10);
    });
  });

  group('readiness + recovery + nutrition', () {
    // 40 → 42.5 kg is +6 %, a normal jump.
    final topReached = [log(now.subtract(const Duration(days: 7)), [(40, 12), (40, 12)])];

    test('a Fatigued prime mover holds an increase', () {
      expect(suggest(topReached).weight, 42.5);
      final s = suggest(topReached, fatigued: const ['Biceps']);
      expect(s.weight, 40);
      expect(s.why.any((w) => w.startsWith('Recovery: biceps Fatigued → repeat last session (40 kg × 12)')), isTrue);
    });

    test('readiness and recovery together repeat, they never lower', () {
      final s = suggest(topReached, readiness: yellow, fatigued: const ['Biceps']);
      expect(s.weight, 40);
      expect(s.why.any((w) => w.contains('Readiness Yellow (45) + biceps Fatigued → repeat last session')), isTrue);
      final grid = GymEquipment.defaults.gridFor(exerciseId: 'bb', kind: EquipmentKind.barbell);
      final c = suggest([log(now.subtract(const Duration(days: 7)), [(65, 5), (65, 5)])],
          range: const RepRange(4, 6), readiness: red, fatigued: const ['Chest'], grid: grid, compound: true, eq: EquipmentKind.barbell);
      expect(c.weight, 65, reason: 'repeat, not a step down');
    });

    test('Red + quads Fatigued on a compound → repeat last session, same weight, all sets', () {
      final grid = GymEquipment.defaults.gridFor(exerciseId: 'm', kind: EquipmentKind.machineCable);
      final s = suggest([log(now.subtract(const Duration(days: 7)), [(40, 8), (40, 7)])],
          range: const RepRange(6, 8), readiness: red, fatigued: const ['Quadriceps'], grid: grid, compound: true, eq: EquipmentKind.machineCable);
      expect(s.weight, 40);
      expect(s.reps, 8);
      expect(s.sets, 3);
      expect(s.why.any((w) => w.contains('Readiness Red (30) + quadriceps Fatigued → repeat last session (40 kg × 8)')), isTrue);
    });

    test('whatever the inputs, never below last time without a freeze', () {
      final grid = GymEquipment.defaults.gridFor(exerciseId: 'm', kind: EquipmentKind.machineCable);
      // A missed range + Red + Fatigued + deficit on a compound.
      final s = suggest([log(now.subtract(const Duration(days: 7)), [(60, 4), (60, 3)])],
          range: const RepRange(6, 8), readiness: red, fatigued: const ['Chest'], grid: grid, compound: true, eq: EquipmentKind.machineCable,
          energy: const EnergyContext(avg7: 100, slopePerWeek: -0.5));
      expect(s.weight, 60);
      expect(s.sets, 3);
    });

    test('a clear deficit changes nothing about holding: falling short holds, with or without it', () {
      final h = [log(now.subtract(const Duration(days: 7)), [(20, 9), (20, 8)])];
      expect(suggest(h).weight, 20);
      final d = suggest(h, energy: const EnergyContext(avg7: 100, slopePerWeek: -0.5));
      expect(d.weight, 20);
      expect(d.why.any((w) => w.contains('deficit')), isTrue);
    });

    test('nutrition never adds load; low protein is a note only', () {
      final h = [log(now.subtract(const Duration(days: 7)), [(20, 11), (20, 10)])];
      final low = suggest(h, energy: const EnergyContext(avg7: 100, protein7: 120, slopePerWeek: 0.3));
      expect(low.weight, 20);
      expect(low.why.any((w) => w.contains('protein 1.2 g/kg')), isTrue);
    });

    test('no nutrition data: skipped and said so', () {
      final s = suggest(topReached.take(1).toList());
      expect(s.why.any((w) => w.startsWith('Nutrition: no nutrition or bodyweight trend data')), isTrue);
    });
  });

  group('bodyweight trend and nutrition model', () {
    test('7-day average and slope from 2–4 weeks of weigh-ins', () {
      final weights = [for (var d = 27; d >= 0; d -= 3) (now.subtract(Duration(days: d)), 108 - (27 - d) * 0.08)];
      final e = EnergyContext.compute(now: now, bodyweights: weights, nutrition: const []);
      expect(e.slopePerWeek, closeTo(-0.56, 0.02));
      expect(e.trend, WeightTrend.losing);
      expect(e.deficit, isTrue);
      expect(e.hasNutrition, isFalse);
      expect(e.describe(), contains('No nutrition data'));
    });

    test('intake 7-day vs 28-day average, protein per kg', () {
      final days = [
        for (var d = 27; d >= 0; d--) DayNutrition(now.subtract(Duration(days: d)), kcal: d < 7 ? 2000 : 2600, proteinG: 150),
      ];
      final e = EnergyContext.compute(now: now, bodyweights: [(now, 106)], nutrition: days);
      expect(e.kcal7, 2000);
      expect(e.deficit, isTrue, reason: '2000 vs ~2450 average');
      expect(e.proteinPerKg, closeTo(1.42, 0.01));
      expect(e.lowProtein, isTrue);
    });

    test('too few weigh-ins → no trend', () {
      final e = EnergyContext.compute(now: now, bodyweights: [(now, 106), (now.subtract(const Duration(days: 2)), 106.4)], nutrition: const []);
      expect(e.slopePerWeek, isNull);
      expect(e.deficit, isFalse);
    });
  });

  group('gym equipment', () {
    test('defaults: dumbbells 2.5–50 by 2.5, barbell in 5 kg steps from 20 (2.5 kg plates), stacks 5 + 5', () {
      expect(dumbbells.values.first, 2.5);
      expect(dumbbells.values.last, 50);
      final bb = GymEquipment.defaults.gridFor(exerciseId: 'b', kind: EquipmentKind.barbell);
      expect(bb.values.take(3), [20, 25, 30]);
      final m = GymEquipment.defaults.gridFor(exerciseId: 'm', kind: EquipmentKind.machineCable);
      expect(m.values.take(3), [5, 10, 15]);
    });

    test('per-exercise stack override; settings round-trip', () {
      const g = GymEquipment(perExercise: {'press': StackSpec(start: 2, step: 7)});
      expect(g.gridFor(exerciseId: 'press', kind: EquipmentKind.machineCable).values.take(3), [2, 9, 16]);
      final back = GymEquipment.decode(g.encode());
      expect(back.perExercise['press'], const StackSpec(start: 2, step: 7));
      expect(back.dumbbells, GymEquipment.defaultDumbbells);
    });

    test('dumbbell list parsing', () {
      expect(GymEquipment.parseDumbbells('2-10/2'), [2, 4, 6, 8, 10]);
      expect(GymEquipment.parseDumbbells('5, 2.5, 7.5'), [2.5, 5, 7.5]);
      expect(GymEquipment.parseDumbbells('abc'), isNull);
    });

    test('assisted: 0 and negative stack positions', () {
      final a = GymEquipment.defaults.gridFor(exerciseId: 'a', kind: EquipmentKind.machineCable, assisted: true);
      expect(a.values.last, 0);
      expect(a.previous(-25), -30);
    });
  });

  group('the routine\'s set count, always', () {
    final barbell = GymEquipment.defaults.gridFor(exerciseId: 'bb', kind: EquipmentKind.barbell);
    final cases = <String, List<ExerciseSessionLog>>{
      'top of range': [log(now.subtract(const Duration(days: 7)), [(65, 8), (65, 8), (65, 8)])],
      'within range': [log(now.subtract(const Duration(days: 7)), [(65, 7), (65, 6), (65, 6)])],
      'below range': [log(now.subtract(const Duration(days: 7)), [(65, 5), (65, 4), (65, 4)])],
      'no history': const [],
    };
    for (final (bandName, r) in [('Green', green), ('Yellow', yellow), ('Red', red)]) {
      for (final recovery in ['Ready', 'Recovering', 'Fatigued']) {
        for (final compound in [true, false]) {
          test('$bandName × $recovery × ${compound ? 'compound' : 'isolation'}', () {
            for (final c in cases.entries) {
              for (final routineSets in [1, 2, 3, 4]) {
                final s = const SuggestionEngine().suggest(SuggestionInput(
                  range: const RepRange(6, 8),
                  targetSets: routineSets,
                  targetRir: 0,
                  increment: 2.5,
                  equipment: EquipmentKind.barbell,
                  history: c.value,
                  readiness: r,
                  now: now,
                  grid: barbell,
                  compound: compound,
                  // Only Fatigued prime movers reach the engine; Ready and Recovering change nothing.
                  fatigued: recovery == 'Fatigued' ? const ['Chest'] : const [],
                ));
                expect(s.sets, routineSets, reason: '${c.key}, $routineSets sets');
                if (c.value.isNotEmpty) {
                  final last = c.value.last.topWeight;
                  expect(s.weight, greaterThanOrEqualTo(last), reason: '${c.key}: never below last time');
                  expect(s.downNote, isNull);
                }
              }
            }
          });
        }
      }
    }
  });
}
