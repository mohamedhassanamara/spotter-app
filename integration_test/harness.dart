import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
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
    final position = tester.state<ScrollableState>(scrollables.last).position;
    final before = position.pixels;
    await tester.drag(scrollables.last, const Offset(0, -320), warnIfMissed: false);
    await settle(2);
    // A drag that starts on a platform view (the embedded YouTube player) goes to the web view, not
    // the list: move the list like the remaining visible part of the page would.
    if ((position.pixels - before).abs() < 1 && position.pixels < position.maxScrollExtent) {
      position.jumpTo((position.pixels + 320).clamp(0, position.maxScrollExtent));
      await settle(2);
    }
  }

  Future<void> scrollToTop() async {
    final scrollables = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    if (scrollables.evaluate().isEmpty) return;
    for (var i = 0; i < 6; i++) {
      await tester.drag(scrollables.last, const Offset(0, 900), warnIfMissed: false);
    }
    final position = tester.state<ScrollableState>(scrollables.last).position;
    if (position.pixels > 0) position.jumpTo(0); // same platform-view case as [_scrollDown]
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

  /// Saves what's on screen as [name].png in `--dart-define=SHOTS_DIR=<host folder>` (simulator runs
  /// can write there), else in the app's Documents/screenshots.
  Future<void> shot(String name) async {
    await settle(4);
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    // The root layer already applies the device pixel ratio: capture its physical-pixel bounds as is.
    final physical = view.size * tester.view.devicePixelRatio;
    await tester.runAsync(() async {
      final image = await layer.toImage(Offset.zero & physical, pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      // SHOTS_DIR: a host folder (the simulator can write to it); otherwise the app's Documents.
      const hostDir = String.fromEnvironment('SHOTS_DIR');
      final base = hostDir.isNotEmpty ? hostDir : '${(await getApplicationDocumentsDirectory()).path}/screenshots';
      final dir = Directory(base)..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    debugPrint('SHOT $name');
  }

  /// A screenshot of the whole simulator screen (status bar, Dynamic Island, home indicator included), not
  /// just Flutter's layer. Needs `--dart-define=SHOTS_DIR=<host folder>` and a host loop that answers
  /// `.req-<name>` files with `xcrun simctl io <id> screenshot` (tool/device_shots.sh); without them it falls
  /// back to [shot].
  Future<void> deviceShot(String name) async {
    const hostDir = String.fromEnvironment('SHOTS_DIR');
    if (hostDir.isEmpty) return shot(name);
    await settle(6);
    final req = File('$hostDir/.req-$name');
    await tester.runAsync(() async {
      Directory(hostDir).createSync(recursive: true);
      req.writeAsStringSync(name);
      final end = DateTime.now().add(const Duration(seconds: 25));
      while (req.existsSync() && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    });
    debugPrint('DEVICE SHOT $name');
  }

  /// Fails the flow if anything was written to the in-app error log.
  Future<void> expectNoLoggedErrors() async {
    await ErrorLog.instance.flush();
    final entries = await ErrorLog.instance.entries();
    expect(entries.map((e) => e.format()).toList(), isEmpty, reason: 'error log must stay empty');
  }
}
