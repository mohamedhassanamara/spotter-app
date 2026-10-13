import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/program/domain/program.dart';

void main() {
  final program = Program.fromJson(jsonDecode(File('assets/programs/min_max_canonical.json').readAsStringSync()) as Map<String, dynamic>);
  final routines = (jsonDecode(File('assets/programs/my_routines.json').readAsStringSync()) as Map<String, dynamic>)['routines']
      as List<dynamic>;

  test('structure: one canonical week, 5 training days, rest days after Lower and Arms, 37 slots', () {
    expect(program.days.map((d) => d.name), ['Upper', 'Lower', 'Push', 'Pull', 'Arms']);
    expect(program.weekLayout, ['Upper', 'Lower', 'Rest', 'Push', 'Pull', 'Arms', 'Rest']);
    expect(program.days.expand((d) => d.slots).length, 37);
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
    expect(s.rir, [0, 2], reason: 'week 5 is canonical');
  });

  test('techniques stay defined (for the manual SET menu) but no prescription carries one', () {
    final sets = prescribeSets(program: program, slotIds: ['lower_01'], sets: 3);
    expect(sets.map((s) => s.targetRir), [0, 0, 0]);
    expect(program.techniques['drop_sets_2x25']!.dropPct, 25);
    expect(program.techniques['lengthened_partials'], isNotNull);
  });

  test('a routine row spanning two slots: Chest Press 2×4-6 then 1×20', () {
    final sets = prescribeSets(program: program, slotIds: ['upper_01', 'upper_02'], sets: 3);
    expect(sets.map((s) => s.repRange), [const RepRange(4, 6), const RepRange(4, 6), const RepRange(20, 20)]);
    expect(sets.map((s) => s.targetRir), [0, 0, 0]);
  });

  test('more sets than the program gives repeat the last set; fewer take the first', () {
    final more = prescribeSets(program: program, slotIds: ['push_04'], sets: 3);
    expect(more.length, 3);
    expect(more.every((s) => s.repRange == const RepRange(20, 20)), isTrue);
    expect(prescribeSets(program: program, slotIds: ['lower_01'], sets: 1).length, 1);
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

  test('warm-up count: higher for the first exercise of the day and compounds, lower otherwise', () {
    final y = program.slot('upper_07')!; // Incline DB Y-Raise, warm-up 0-1
    expect(warmupCountFor(y, firstOfDay: false, compound: false), 0);
    expect(warmupCountFor(y, firstOfDay: true, compound: false), 1);
    final press = program.slot('upper_01')!; // warm-up 2-3
    expect(warmupCountFor(press, firstOfDay: false, compound: true), 3);
    expect(warmupCountFor(press, firstOfDay: false, compound: false), 2);
  });

  test('planned rest days and 5 sessions a week; one RIR per working set in every slot', () {
    expect(program.plannedRestWeekdays, {DateTime.wednesday, DateTime.sunday});
    expect(program.sessionsPerWeek, 5);
    for (final d in program.days) {
      for (final s in d.slots) {
        expect(s.rir.length, s.workingSets, reason: s.id);
      }
    }
  });

  test('the canonical file is week 5 of the 12-week extraction, with no weeks or techniques', () {
    final full = jsonDecode(File('docs/program/min_max_phase2_12weeks.json').readAsStringSync()) as Map<String, dynamic>;
    final canon = jsonDecode(File('assets/programs/min_max_canonical.json').readAsStringSync()) as Map<String, dynamic>;
    expect((canon['program'] as Map)['canonical_week'], 5);
    for (final (i, d) in (full['days'] as List).indexed) {
      for (final (k, s) in ((d as Map)['slots'] as List).indexed) {
        final c = (((canon['days'] as List)[i] as Map)['slots'] as List)[k] as Map;
        expect(c['rir'], (((s as Map)['weeks'] as Map)['5'] as Map)['rir'], reason: s['slot_id'] as String);
        expect(c.containsKey('weeks'), isFalse);
      }
    }
  });

  test('my routines no longer include Face Pull; Back Extension is confirmed', () {
    final names = [
      for (final r in routines.cast<Map<String, dynamic>>())
        for (final e in (r['exercises'] as List<dynamic>).cast<Map<String, dynamic>>()) e['name'],
    ];
    expect(names, isNot(contains('Face Pull')));
    expect(names.length, 29);
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
