import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/load_kinds.dart';
import 'package:spotter/features/program/data/program_repository.dart';
import 'package:spotter/features/program/domain/program.dart';

import 'harness.dart';

/// Host folder for docs/program/FIDELITY.md (the simulator can write there).
const _reportDir = String.fromEnvironment('REPORT_DIR');

String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

String _ranges(List<RepRange> rs) {
  final parts = <String>[];
  RepRange? cur;
  var n = 0;
  for (final r in [...rs, null]) {
    if (r != cur) {
      if (n > 0) parts.add('$n×$cur');
      cur = r;
      n = 0;
    }
    n++;
  }
  return parts.join(' · ');
}

String _text(Finder f) {
  final w = f.evaluate().first.widget;
  return w is Text ? (w.data ?? w.textSpan!.toPlainText()) : (w as RichText).text.toPlainText();
}

/// One finished session a few days ago for every routine exercise, so suggestions aren't in
/// calibration (calibration skips warm-ups) and the logger renders the full prescription.
Future<void> _seedHistory(AppDatabase db) async {
  final rows = await db.select(db.routineExercises).get();
  final when = DateTime.now().subtract(const Duration(days: 4));
  final sid = await db.into(db.sessions).insert(SessionsCompanion.insert(name: 'Seed', startedAt: when, status: const Value('finished'), endedAt: Value(when.add(const Duration(hours: 1)))));
  for (final (i, r) in rows.indexed) {
    final ex = await db.into(db.sessionExercises).insert(SessionExercisesCompanion.insert(
          sessionId: sid,
          exerciseId: r.exerciseId,
          position: i,
          repMin: r.repMin,
          repMax: r.repMax,
          targetSets: r.targetSets,
          restSeconds: r.restSeconds,
        ));
    final w = isAssisted(r.exerciseId) ? -20.0 : 20.0;
    for (var k = 0; k < 2; k++) {
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
            sessionExerciseId: ex,
            position: k,
            weight: Value(w),
            reps: Value(r.repMin),
            rpe: const Value(9),
            completed: const Value(true),
            completedAt: Value(when),
            targetRepMin: Value(r.repMin),
            targetRepMax: Value(r.repMax),
          ));
    }
  }
  // History reloads on session-table changes: touch the session now that its sets exist.
  await (db.update(db.sessions)..where((t) => t.id.equals(sid))).write(const SessionsCompanion(notes: Value('seeded')));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fix 5: program fidelity. What the logger renders for all 5 routines matches the canonical week '
      '(sets, reps, RIR, warm-ups, rest, supersets) plus my documented swaps and set counts', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;
    await tester.runAsync(() => _seedHistory(db));
    final program = (await tester.runAsync(ProgramRepository.load))!;
    final mine = (await tester.runAsync(ProgramRepository.loadMyRoutines))!;
    final catalog = (await tester.runAsync(() => ExerciseRepository(db).watchCatalog().first))!;

    final table = <String>[
      '| Routine | Exercise (program slot) | Sets: program / mine / logger | Reps: program / logger | Effort per set: program / logger | Warm-ups: rule / logger | Rest: program / logger | Superset | |',
      '|---|---|---|---|---|---|---|---|---|',
    ];
    final mismatches = <String>[];

    for (final (ri, routine) in (mine['routines'] as List).cast<Map<String, dynamic>>().indexed) {
      final name = routine['name'] as String;
      debugPrint('STEP $name');
      await h.goTab(Icons.fitness_center_outlined);
      await h.scrollToTop();
      await h.tap(find.text('Start').at(ri));
      await h.waitFor(find.text('Finish'), scroll: false);
      final session = (await tester.runAsync(() => (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle()))!;
      final exs = (await tester.runAsync(() => (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get()))!;
      final defs = (routine['exercises'] as List).cast<Map<String, dynamic>>();
      expect(exs.length, defs.length, reason: '$name: every routine row is in the logger');
      final groupOfLabel = <String, int?>{};

      for (final (i, def) in defs.indexed) {
        final ex = exs[i];
        final slotIds = (def['program_slots'] as List).cast<String>();
        final slots = [for (final id in slotIds) program.slot(id)!];
        final first = slots.first;
        final mySets = def['sets'] as int;
        final programSets = slots.fold(0, (a, s) => a + s.workingSets);
        final pres = prescribeSets(program: program, slotIds: slotIds, sets: mySets);
        final info = catalog[ex.exerciseId]!;
        final expWarmups = warmupCountFor(first, firstOfDay: i == 0, compound: info.isCompound);
        final expEffort = [for (final p in pres) Effort.fromRir(p.targetRir).label];
        final label = first.superset;
        final pairEnd = label != null && slots.first.rest != null;
        final expRest = label == null
            ? 'Rest Timer ${_clock(first.rest!.maxSeconds)}'
            : (pairEnd ? 'Rest ${_clock(first.rest!.maxSeconds)} after the round' : 'No rest →');

        // What the logger renders, read off the widgets.
        final sets = (await tester.runAsync(() => (db.select(db.workoutSets)
              ..where((t) => t.sessionExerciseId.equals(ex.id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get()))!;
        await h.waitFor(find.byKey(ValueKey('rest-text-${ex.id}')), reason: '${def['name']} block');
        final restShown = _text(find.byKey(ValueKey('rest-text-${ex.id}')));
        final prescription = _text(find.descendant(of: find.byKey(ValueKey('prescription-${ex.id}')), matching: find.byType(Text)).first);
        final ssShown = find.byKey(ValueKey('superset-label-${ex.id}')).evaluate().isEmpty ? null : _text(find.byKey(ValueKey('superset-label-${ex.id}')));
        var warmShown = 0;
        final working = <String>[];
        for (final s in sets) {
          await h.waitFor(find.byKey(ValueKey('set-label-${s.id}')));
          final setLabel = _text(find.descendant(of: find.byKey(ValueKey('set-label-${s.id}')), matching: find.byType(Text)).first);
          if (setLabel == 'W') {
            warmShown++;
          } else {
            working.add(_text(find.byKey(ValueKey('effort-label-${s.id}'))));
          }
        }

        final problems = <String>[
          if (working.length != mySets) 'sets ${working.length} ≠ $mySets',
          if (!prescription.contains(_ranges([for (final p in pres) p.repRange]))) 'reps "$prescription"',
          if (working.join('/') != expEffort.join('/')) 'effort ${working.join('/')} ≠ ${expEffort.join('/')}',
          if (warmShown != expWarmups) 'warm-ups $warmShown ≠ $expWarmups',
          if (!restShown.startsWith(expRest)) 'rest "$restShown"',
          if ((label == null) != (ssShown == null)) 'superset label ${ssShown ?? 'missing'}',
          if (label != null && groupOfLabel.containsKey(label) && groupOfLabel[label] != ex.supersetGroup) 'superset grouping',
        ];
        if (label != null) groupOfLabel.putIfAbsent(label, () => ex.supersetGroup);
        final relation = def['relation'] as String? ?? 'program';
        final exerciseCell = '${def['name']}${relation == 'program' ? '' : ' (${relation == 'swap' ? 'my swap' : 'substitution'} for ${first.exercise})'} `${slotIds.join('+')}`';
        final setsCell = '$programSets / $mySets${mySets != programSets ? ' (mine)' : ''} / ${working.length}';
        table.add('| $name | $exerciseCell | $setsCell | ${_ranges([for (final p in pres) p.repRange])} / ${prescription.split(' · ').where((p) => p.contains('×')).join(' · ')} | '
            '${expEffort.join(' ')} / ${working.join(' ')} | $expWarmups / $warmShown | ${first.rest?.text ?? '– (superset)'} / $restShown | '
            '${label == null ? '–' : '${first.superset} → $ssShown'} | ${problems.isEmpty ? '✓' : '✗ ${problems.join('; ')}'} |');
        if (problems.isNotEmpty) mismatches.add('$name / ${def['name']}: ${problems.join('; ')}');
      }

      await h.scrollToTop();
      await h.tap(find.text('Discard workout'));
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Discard')));
      await h.settle();
    }

    final report = [
      '# Program fidelity: canonical week vs. what the logger renders',
      '',
      'Generated by `integration_test/program_fidelity_test.dart` on the simulator: each routine is started and the logger\'s '
          'widgets are read (working set rows, the effort chip on each, warm-up rows, the prescription line, the rest line, the '
          'superset label), then compared with `assets/programs/min_max_canonical.json` (the PDF\'s week 5) and my documented '
          'swaps and set counts in `assets/programs/my_routines.json`. Neutral readiness, history seeded so no exercise is in calibration.',
      '',
      '- Warm-ups follow the app\'s rule: the high end of the program\'s range for the day\'s first exercise and compounds, the low end otherwise.',
      '- Rest is the top of the program\'s range. In a superset the first exercise has no rest and the round ends with the listed rest.',
      '- "mine" marks a set count that differs from the program on purpose (documented in DECISIONS.md).',
      '',
      ...table,
      '',
      mismatches.isEmpty ? '**All rows match.**' : '**Mismatches:**\n${mismatches.map((m) => '- $m').join('\n')}',
      '',
    ].join('\n');
    debugPrint(report);
    if (_reportDir.isNotEmpty) {
      await tester.runAsync(() async => File('$_reportDir/FIDELITY.md').writeAsString(report));
    }
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
