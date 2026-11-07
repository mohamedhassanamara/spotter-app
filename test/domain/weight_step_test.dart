import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/weight_step.dart';
import 'package:spotter/core/providers.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/workout/presentation/keypad.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('defaults by equipment come from the one table', () {
    expect(defaultStepFor(equipment: 'barbell'), 2.5);
    expect(defaultStepFor(equipment: 'e-z curl bar'), 2.5);
    expect(defaultStepFor(equipment: 'dumbbell'), 2);
    expect(defaultStepFor(equipment: 'machine', name: 'Seated Row'), 5);
    expect(defaultStepFor(equipment: 'machine', name: 'Plate Loaded Chest Press'), 5);
    expect(defaultStepFor(equipment: 'cable'), 2.5);
    expect(defaultStepFor(equipment: 'machine', name: 'Smith Machine Squat'), 2.5);
    expect(defaultStepFor(equipment: 'dumbbell', name: 'X', isCustom: true), 2.5, reason: 'custom exercises');
    expect(defaultStepFor(equipment: null), 2.5);
  });

  test('labels: no trailing zeros, kg and lb', () {
    expect(stepLabel(2, -1), '−2');
    expect(stepLabel(2, 1), '+2');
    expect(stepLabel(1.25, 1), '+1.25');
    expect(stepLabel(0.5, -1), '−0.5');
    expect(stepLabel(2.5, 1), '+2.5');
    expect(stepLabel(10, 1), '+10');
    expect(stepLabel(2.5, 1, unit: WeightUnit.lb), '+5.51');
    expect(stepLabel(5, -1, unit: WeightUnit.lb), '−11.02');
  });

  test('stepping rounds: floats never show noise', () {
    var w = 0.0;
    for (var i = 0; i < 3; i++) {
      w = stepWeight(w, 1, 0.1);
    }
    expect(w, 0.3, reason: '0.1 + 0.1 + 0.1 is 0.30000000000000004 in floats');
    expect(KeypadBuffer.formatPlain(w), '0.3');
    expect(stepWeight(22.5, -1, 2.5), 20);
    expect(stepWeight(1, -1, 2.5), 0, reason: 'never below 0');
    expect(stepWeight(-10, -1, 2.5, allowNegative: true), -12.5, reason: 'assisted');
    expect(stepWeight(48, 1, 5, cap: 50), 50, reason: 'max load');
  });

  test('keypad buffer follows the step it is given (the label and the move are the same number)', () {
    final b = KeypadBuffer(field: KeypadField.kg)..set(20);
    b.step(1, increment: 1.25, fallback: 0);
    expect(b.text, '21.25');
    b.step(-1, increment: 2, fallback: 0);
    expect(b.text, '19.25');
    final c = KeypadBuffer(field: KeypadField.kg)..set(0.2);
    c.step(1, increment: 0.1, fallback: 0);
    expect(c.text, '0.3');
  });

  test('override beats the default; non-positive overrides are ignored', () {
    expect(resolveStep(null, 2.5), 2.5);
    expect(resolveStep(1.25, 2.5), 1.25);
    expect(resolveStep(0, 2.5), 2.5);
  });

  test('the step persists per exercise (settings), is read back and can be reset', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = SettingsController(db);
    await c.setExerciseStep('a', 1.25);
    await c.setExerciseStep('b', 10);
    var s = SettingsModel.fromMap({SettingsModel.kExerciseSteps: (await db.getSetting(SettingsModel.kExerciseSteps))!});
    expect(s.exerciseSteps, {'a': 1.25, 'b': 10});
    await c.setExerciseStep('a', null);
    s = SettingsModel.fromMap({SettingsModel.kExerciseSteps: (await db.getSetting(SettingsModel.kExerciseSteps))!});
    expect(s.exerciseSteps, {'b': 10.0});
    expect(decodeExerciseSteps('not json'), isEmpty);
  });

  testWidgets('keypad buttons show the step and update when it changes; long-press opens the picker callback', (tester) async {
    var long = 0;
    Widget pad(double step, WeightUnit unit) => MaterialApp(
          home: Scaffold(
            body: WorkoutKeypad(
              field: KeypadField.kg,
              increment: step,
              unit: unit,
              onStepLongPress: () => long++,
              signToggle: false,
              onDigit: (_) {},
              onDot: () {},
              onBackspace: () {},
              onStep: (_) {},
              onCopy: () {},
              onSign: () {},
              onNext: () {},
              onHide: () {},
            ),
          ),
        );
    await tester.pumpWidget(ProviderScope(child: pad(2, WeightUnit.kg)));
    expect(find.text('−2'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    await tester.pumpWidget(ProviderScope(child: pad(1.25, WeightUnit.kg)));
    expect(find.text('−1.25'), findsOneWidget);
    expect(find.text('+1.25'), findsOneWidget);
    await tester.pumpWidget(ProviderScope(child: pad(2.5, WeightUnit.lb)));
    expect(find.text('+5.51'), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('key-plus-inc')));
    expect(long, 1);
  });
}
