import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'harness.dart';

final _weekN = RegExp(r'\bWeek \d+', caseSensitive: false);

bool _anyWeekText() => find.byWidgetPredicate((w) {
      final t = w is Text ? (w.data ?? w.textSpan?.toPlainText()) : (w is RichText ? w.text.toPlainText() : null);
      return t != null && _weekN.hasMatch(t);
    }).evaluate().isNotEmpty;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fix 0: one fixed week. No "Week N" anywhere, every routine starts with working sets only, '
      'Settings → Program describes the fixed template', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();

    expect(_anyWeekText(), isFalse, reason: 'Home');
    await h.goTab(Icons.fitness_center_outlined);
    await h.waitFor(find.text('Start empty workout'));
    for (final (i, name) in ['Upper', 'Lower', 'Push', 'Pull', 'Arms'].indexed) {
      debugPrint('STEP start $name');
      await h.scrollToTop();
      await h.tap(find.text('Start').at(i));
      await h.waitFor(find.text('Finish'), scroll: false);
      expect(find.text(name), findsWidgets, reason: 'the header shows just the day');
      expect(_anyWeekText(), isFalse, reason: '$name logger');
      final db = h.db!;
      final session = (await tester.runAsync(() => (db.select(db.sessions)..where((t) => t.status.equals('active'))).getSingle()))!;
      final exs = (await tester.runAsync(() => (db.select(db.sessionExercises)
            ..where((t) => t.sessionId.equals(session.id))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get()))!;
      final sets = (await tester.runAsync(() => (db.select(db.workoutSets)..where((t) => t.sessionExerciseId.isIn([for (final e in exs) e.id]))).get()))!;
      expect(sets.where((s) => s.setType != null), isEmpty, reason: '$name: no automatic drop / myo / hold sets');
      expect(sets.where((s) => s.technique != null), isEmpty, reason: '$name: no technique tags');
      expect(exs.every((e) => e.programWeek == null), isTrue);
      await h.scrollToTop();
      await h.tap(find.text('Discard workout'));
      await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Discard')));
      await h.goTab(Icons.fitness_center_outlined);
      await h.scrollToTop();
      await h.waitFor(find.text('Start empty workout'), scroll: false);
    }

    debugPrint('STEP Settings → Program');
    await h.goTab(Icons.home_outlined);
    await h.tap(find.byTooltip('Settings'));
    await h.waitFor(find.textContaining('One fixed weekly template'), reason: 'Program tile');
    expect(_anyWeekText(), isFalse, reason: 'Settings');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
