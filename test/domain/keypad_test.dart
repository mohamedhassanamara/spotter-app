import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/workout/presentation/keypad.dart';

void main() {
  test('digits, one decimal point for kg only, backspace', () {
    final kg = KeypadBuffer(field: KeypadField.kg);
    for (final d in ['6', '2']) {
      kg.digit(d);
    }
    kg.dot();
    kg.dot();
    kg.digit('5');
    expect(kg.text, '62.5');
    kg.backspace();
    expect(kg.text, '62.');
    final reps = KeypadBuffer(field: KeypadField.reps);
    reps.dot();
    expect(reps.text, '');
  });

  test('± uses the equipment increment, starting from the cell value when nothing is typed', () {
    final kg = KeypadBuffer(field: KeypadField.kg);
    kg.step(1, increment: 1.25, fallback: 20);
    expect(kg.value, 21.25);
    kg.step(-1, increment: 1.25, fallback: 0);
    expect(kg.value, 20);
    final reps = KeypadBuffer(field: KeypadField.reps);
    reps.step(1, increment: 2.5, fallback: 8);
    expect(reps.value, 9, reason: 'reps always step by 1');
  });

  test('sign toggle for assisted loads', () {
    final kg = KeypadBuffer(field: KeypadField.kg, text: '-');
    expect(kg.isEmpty, isTrue);
    kg.digit('4');
    kg.digit('0');
    expect(kg.value, -40);
    kg.toggleSign();
    expect(kg.value, 40);
  });
}
