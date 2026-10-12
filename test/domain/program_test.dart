import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/program/domain/program.dart';

void main() {
  final program = Program.fromJson(jsonDecode(File('assets/programs/min_max_phase2.json').readAsStringSync()) as Map<String, dynamic>);
  final routines = (jsonDecode(File('assets/programs/my_routines.json').readAsStringSync()) as Map<String, dynamic>)['routines']
      as List<dynamic>;

  test('structure: 12 weeks, 5 training days, rest days after Lower and Arms, 37 slots', () {
    expect(program.weekCount, 12);
    expect(program.days.map((d) => d.name), ['Upper', 'Lower', 'Push', 'Pull', 'Arms']);
    expect(program.weekLayout, ['Upper', 'Lower', 'Rest', 'Push', 'Pull', 'Arms', 'Rest']);
    expect(program.days.expand((d) => d.slots).length, 37);
    expect(program.introWeeks, {1, 7});
  });

  test('slot details as printed (Lower: Hack Squat)', () {
    final s = program.slot('lower_02')!;
    expect(s.exercise, 'Hack Squat');
    expect(s.warmupSets.min, 2);
    expect(s.warmupSets.max, 3);
    expect(s.repRange, const RepRange(4, 6));
    expect(s.rest!.maxSeconds, 240);
    expect(s.substitutions, ['Smith Machine Squat', 'Leg Press']);
    expect(s.rir0AttemptFailure, isFalse, reason: 'RIR 0 safety rule');
    expect(s.week(1).rir, [2, 3]);
    expect(s.week(5).rir, [0, 2]);
    expect(s.week(8).rir, [1, 2]);
  });

  test('techniques only in block 2 (weeks 8-12), on the last working set', () {
    final legCurl = program.slot('lower_01')!;
    expect(legCurl.week(7).technique, isNull);
    expect(legCurl.week(8).technique, 'drop_sets_2x25');
    final sets = prescribeSets(program: program, slotIds: ['lower_01'], sets: 3, week: 8);
    expect(sets.map((s) => s.technique), [null, null, 'drop_sets_2x25']);
    expect(sets.map((s) => s.targetRir), [0, 0, 0]);
    expect(program.techniques['drop_sets_2x25']!.dropPct, 25);
    expect(program.techniques['lengthened_partials'], isNotNull);
  });

  test('a routine row spanning two slots: Chest Press 2×4-6 then 1×20', () {
    final sets = prescribeSets(program: program, slotIds: ['upper_01', 'upper_02'], sets: 3, week: 2);
    expect(sets.map((s) => s.repRange), [const RepRange(4, 6), const RepRange(4, 6), const RepRange(20, 20)]);
    expect(sets.map((s) => s.targetRir), [0, 0, 0]);
    final intro = prescribeSets(program: program, slotIds: ['upper_01', 'upper_02'], sets: 3, week: 1);
    expect(intro.map((s) => s.targetRir), [1, 2, 1]);
  });

  test('more sets than the program gives repeat the last set; fewer take the first', () {
    final more = prescribeSets(program: program, slotIds: ['push_04'], sets: 3, week: 2);
    expect(more.length, 3);
    expect(more.every((s) => s.repRange == const RepRange(20, 20)), isTrue);
    expect(prescribeSets(program: program, slotIds: ['lower_01'], sets: 1, week: 2).length, 1);
  });

  test('warm-up pyramids from the program (planned working weight 100 kg, 2.5 kg plates)', () {
    List<double> w(int n) => [for (final s in warmupSets(program: program, count: n, workingWeight: 100, increment: 2.5)) s.weight];
    expect(w(0), isEmpty);
    expect(w(1), [60]);
    expect(w(2), [50, 70]);
    expect(w(3), [45, 65, 85]);
    expect(w(4), [45, 60, 75, 85]);
    final three = warmupSets(program: program, count: 3, workingWeight: 100, increment: 2.5);
    expect(three.map((s) => s.reps), [6, 4, 3]);
    // Rounded to the increment, never below one increment.
    expect(warmupSets(program: program, count: 2, workingWeight: 23, increment: 2).map((s) => s.weight), [12, 16]);
    expect(warmupSets(program: program, count: 1, workingWeight: 2, increment: 2).single.weight, 2);
  });

  test('program week loops after week 12', () {
    final start = DateTime(2026, 9, 7); // Monday
    expect(programWeekFor(startMonday: start, now: DateTime(2026, 9, 7), weekCount: 12), 1);
    expect(programWeekFor(startMonday: start, now: DateTime(2026, 9, 13, 20), weekCount: 12), 1);
    expect(programWeekFor(startMonday: start, now: DateTime(2026, 9, 14), weekCount: 12), 2);
    expect(programWeekFor(startMonday: start, now: DateTime(2026, 11, 30), weekCount: 12), 1);
    expect(startMondayForWeek(week: 6, now: DateTime(2026, 10, 14)), DateTime(2026, 9, 7));
  });

  test('my routines: every slot exists, set counts match the program except the flagged extra', () {
    for (final r in routines.cast<Map<String, dynamic>>()) {
      for (final e in (r['exercises'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final slots = (e['program_slots'] as List<dynamic>).cast<String>();
        expect(slots.every((s) => program.slot(s) != null), isTrue, reason: e['name'] as String);
        final total = slots.fold<int>(0, (a, s) => a + program.slot(s)!.workingSets);
        if (e['relation'] != 'extra') expect(total, e['sets'], reason: e['name'] as String);
      }
    }
  });
}
