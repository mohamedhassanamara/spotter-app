import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/equipment.dart';
import 'package:spotter/core/domain/gym.dart';
import 'package:spotter/core/domain/load_types.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';
import 'package:spotter/features/readiness/domain/readiness.dart';
import 'package:spotter/features/workout/presentation/keypad.dart';

ExerciseSessionLog log(List<(double, int)> sets, {int day = 1}) => ExerciseSessionLog(
      sessionId: day,
      date: DateTime(2026, 5, day),
      suggestionKind: SuggestionKind.none,
      sets: [for (final s in sets) LoggedSet(weight: s.$1, reps: s.$2, rpe: 8)],
    );

const id = 'Butterfly';
final capped = const GymEquipment().copyWith(maxLoads: {id: 50}, typeOverrides: {id: LoadType.stack}, perExercise: {id: const StackSpec(start: 2.5, step: 2.5)});
WeightGrid grid({Iterable<double> logged = const []}) => capped.gridFor(exerciseId: id, type: LoadType.stack, logged: logged);

Suggestion suggest(List<ExerciseSessionLog> h, {WeightGrid? g, RepRange range = const RepRange(8, 12)}) => const SuggestionEngine().suggest(SuggestionInput(
      range: range,
      targetSets: 3,
      targetRir: 2,
      increment: 5,
      equipment: EquipmentKind.machineCable,
      history: h,
      readiness: ExerciseReadiness.neutral,
      now: DateTime(2026, 5, 10),
      grid: g ?? grid(),
    ));

void main() {
  test('the grid stops at the max load, even over weights you logged above it', () {
    final g = grid(logged: [55, 60]);
    expect(g.values.last, 50);
    expect(g.next(50), isNull);
    expect(g.atMax(50), isTrue);
    expect(g.atMax(45), isFalse);
    expect(const GymEquipment(perExercise: {id: StackSpec(start: 2.5, step: 2.5)}).gridFor(exerciseId: id, type: LoadType.stack).maxLoad, isNull);
  });

  test('max load survives the settings round trip; absent = unlimited', () {
    final back = GymEquipment.decode(capped.encode());
    expect(back.maxLoads, {id: 50});
    expect(GymEquipment.decode(const GymEquipment().encode()).maxLoads, isEmpty);
  });

  test('below the max the next suggestion is the next plate, never above the max', () {
    final s = suggest([log([(47.5, 12), (47.5, 12), (47.5, 12)])]);
    expect(s.weight, 50);
    expect(s.maxReached, isTrue, reason: 'it lands on the max');
    final over = suggest([log([(55, 8), (55, 8), (55, 8)])]);
    expect(over.weight, lessThanOrEqualTo(50));
  });

  test('at the max with the top of the range hit: same weight, reps keep growing past the range', () {
    var s = suggest([log([(50, 12), (50, 12), (50, 12)])]);
    expect(s.weight, 50);
    expect(s.kind, SuggestionKind.addReps);
    expect(s.reps, 13);
    expect(s.maxReached, isTrue);
    expect(s.why.join(' '), contains(maxReachedMessage));
    s = suggest([log([(50, 16), (50, 16), (50, 16)])]);
    expect(s.reps, 17, reason: 'no cap at range.max + 3 once the weight cannot go up');
  });

  test('without a max the old behaviour holds (increase, no message)', () {
    final s = suggest([log([(47.5, 12), (47.5, 12), (47.5, 12)])], g: const GymEquipment(perExercise: {id: StackSpec(start: 2.5, step: 2.5)}).gridFor(exerciseId: id, type: LoadType.stack));
    expect(s.weight, 50);
    expect(s.maxReached, isFalse);
  });

  test('keypad + never goes above the max load; − still works', () {
    final b = KeypadBuffer(field: KeypadField.kg)..set(47.5);
    b.step(1, increment: 5, fallback: 0, grid: grid());
    expect(b.value, 50);
    b.step(1, increment: 5, fallback: 0, grid: grid());
    expect(b.value, 50, reason: 'already at the max');
    b.set(60);
    b.step(1, increment: 5, fallback: 0, grid: grid());
    expect(b.value, 50);
    b.step(-1, increment: 5, fallback: 0, grid: grid());
    expect(b.value, 47.5);
  });
}
