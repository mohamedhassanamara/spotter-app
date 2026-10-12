import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotter/app.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/core/diagnostics/error_log.dart';
import 'package:spotter/core/providers.dart';
import 'package:spotter/bootstrap.dart';

/// Shared helpers for the tap-driven flows. Every flow starts from a fresh install.
class AppHarness {
  AppHarness(this.tester);
  final WidgetTester tester;
  AppDatabase? db;

  /// Extra provider overrides (e.g. a fixture instead of the iOS document picker).
  List<Override> overrides = const [];

  /// Deletes the database (fresh install), opens a new one, launches the app.
  Future<void> launchFresh({List<Override> overrides = const []}) async {
    this.overrides = overrides;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final docs = await getApplicationDocumentsDirectory();
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('${docs.path}/spotter.sqlite$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    await ErrorLog.instance.init();
    await ErrorLog.instance.clear();
    db = AppDatabase.open();
    await bootstrapDatabase(db!);
    await pumpApp();
  }

  /// (Re)builds the widget tree on the current database, like a cold start.
  Future<void> pumpApp() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db!), ...overrides],
      child: const SpotterApp(),
    ));
    await settle();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await db?.close();
  }

  /// Pumps frames (with real async gaps for DB work) without waiting for repeating animations.
  Future<void> settle([int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Pumps until [finder] matches or fails with a helpful message.
  Future<void> waitFor(Finder finder, {Duration timeout = const Duration(seconds: 20), String? reason, bool scroll = true}) async {
    final end = DateTime.now().add(timeout);
    var attempts = 0;
    while (DateTime.now().isBefore(end)) {
      if (finder.evaluate().isNotEmpty) return;
      await settle(2);
      // Lists build lazily: after a few tries, scroll down like a person would.
      if (scroll && ++attempts > 3 && attempts % 2 == 0) await _scrollDown();
    }
    final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText()).whereType<String>().take(60).join(' | ');
    throw TestFailure('Timed out waiting for ${reason ?? finder}\nOn screen: $texts');
  }

  Future<void> _scrollDown() async {
    final scrollables = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    if (scrollables.evaluate().isEmpty) return;
    await tester.drag(scrollables.last, const Offset(0, -320), warnIfMissed: false);
    await settle(2);
  }

  Future<void> scrollToTop() async {
    final scrollables = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    if (scrollables.evaluate().isEmpty) return;
    for (var i = 0; i < 6; i++) {
      await tester.drag(scrollables.last, const Offset(0, 900), warnIfMissed: false);
    }
    await settle(2);
  }

  Future<void> tap(Finder finder, {String? reason}) async {
    await waitFor(finder, reason: reason);
    await tester.ensureVisible(finder.first);
    await settle(2);
    await tester.tap(finder.first, warnIfMissed: false);
    await settle();
  }

  Future<void> longPress(Finder finder) async {
    await waitFor(finder);
    await tester.ensureVisible(finder.first);
    await settle(2);
    await tester.longPress(finder.first, warnIfMissed: false);
    await settle();
  }

  /// Onboarding with a bodyweight (needed for ranks and assisted lifts), no Health.
  Future<void> onboard({String bodyweight = '80'}) async {
    await waitFor(find.text('Spotter'), reason: 'onboarding');
    await tester.enterText(find.byType(TextField).first, bodyweight);
    await settle(3);
    await tap(find.text('Next'));
    await tap(find.text('Not now'));
    await tap(find.text("Let's lift"));
    await waitFor(find.byIcon(Icons.fitness_center_outlined), reason: 'home after onboarding');
    // Program routines install right after the first frame.
    for (var i = 0; i < 30; i++) {
      final routines = await tester.runAsync(() => db!.select(db!.routines).get());
      if ((routines ?? const []).length == 5) break;
      await settle(3);
    }
  }

  Future<void> goTab(IconData icon) => tap(find.byIcon(icon));

  /// Fails the flow if anything was written to the in-app error log.
  Future<void> expectNoLoggedErrors() async {
    await ErrorLog.instance.flush();
    final entries = await ErrorLog.instance.entries();
    expect(entries.map((e) => e.format()).toList(), isEmpty, reason: 'error log must stay empty');
  }
}
