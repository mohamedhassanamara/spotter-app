import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/presentation/exercise_thumb.dart';

import 'harness.dart';

/// No thumbnail may contain a network photo: only the GIF still (RawImage) or the generated figure.
void _expectNoPhotoThumbs() {
  final photos = find.descendant(of: find.byType(ExerciseThumb), matching: find.byType(Image));
  expect(photos, findsNothing, reason: 'thumbnails are never photos');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fix 3: thumbnails are GIF stills or generated muscle figures everywhere; photos only in the '
      "exercise page's Photos section", (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard();
    final db = h.db!;

    // Media matching runs in the background after launch.
    for (var i = 0; i < 60; i++) {
      final n = (await tester.runAsync(() => db.select(db.mediaMatches).get()))!.length;
      if (n > 2000) break;
      await h.settle(5);
    }
    final catalog = (await tester.runAsync(() => ExerciseRepository(db).watchCatalog().first))!;
    final matches = {for (final m in (await tester.runAsync(() => db.select(db.mediaMatches).get()))!) m.exerciseId: m};
    final withGif = catalog['Barbell_Curl']!;
    expect(matches[withGif.id]?.gifUrl, isNotNull);
    // A library exercise with photos but no GIF.
    final photoOnly = catalog.values.firstWhere((e) => e.imageUrls.isNotEmpty && matches[e.id]?.gifUrl == null && !e.name.contains('(') && e.name.length < 28);
    debugPrint('photo-only exercise: ${photoOnly.name}');

    debugPrint('STEP library: GIF still for ${withGif.name}');
    await h.goTab(Icons.menu_book_outlined);
    await tester.enterText(find.byType(TextField).first, withGif.name);
    await h.settle(6);
    await h.waitFor(find.byKey(ValueKey('thumb-gif-${withGif.id}')), timeout: const Duration(seconds: 40), reason: 'GIF first frame', scroll: false);
    _expectNoPhotoThumbs();

    debugPrint('STEP library: generated figure for ${photoOnly.name} (it has photos, but they never become the thumbnail)');
    await tester.enterText(find.byType(TextField).first, photoOnly.name);
    await h.settle(6);
    await h.waitFor(find.byKey(ValueKey('thumb-generated-${photoOnly.id}')), scroll: false);
    _expectNoPhotoThumbs();
    await h.shot('library-thumbs');

    debugPrint('STEP its page: generated demo on top, photos in the Photos section');
    await h.tap(find.text(photoOnly.name).last);
    await h.waitFor(find.byKey(const ValueKey('demo-generated')), scroll: false);
    await h.waitFor(find.byKey(const ValueKey('photos-section')), reason: 'Photos section');
    await h.scrollToTop();
    await tester.pageBack();
    await h.settle();

    debugPrint('STEP logger and routine editor thumbnails');
    await h.goTab(Icons.fitness_center_outlined);
    await h.tap(find.text('Push'));
    await h.waitFor(find.byType(ExerciseThumb));
    _expectNoPhotoThumbs();
    await tester.pageBack();
    await h.settle();
    await h.scrollToTop();
    await h.tap(find.text('Start').at(2));
    await h.waitFor(find.byType(ExerciseThumb));
    await h.settle(20);
    _expectNoPhotoThumbs();
    await h.scrollToTop();
    await h.tap(find.text('Discard workout'));
    await h.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Discard')));

    debugPrint('STEP history thumbnails');
    await tester.runAsync(() async {
      final s = LiftoffImportService(db);
      final t = DateTime.now().subtract(const Duration(days: 2));
      String two(int v) => v.toString().padLeft(2, '0');
      final csv = 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
          '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00,01 hours 00 minutes 00 seconds,,EZ Bar Curl,0,88.2,8,0,0,,6-8\n';
      await s.commit(await s.preview(csv, catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    final session = (await tester.runAsync(() => (db.select(db.sessions)..orderBy([(t) => OrderingTerm.desc(t.startedAt)])).get()))!.first;
    await h.goTab(Icons.insights_outlined);
    await h.tap(find.descendant(of: find.byType(TabBar), matching: find.text('History')));
    await h.settle(6);
    await h.tap(find.text(session.name).first);
    await h.waitFor(find.byType(ExerciseThumb), reason: 'history exercise thumbnail');
    _expectNoPhotoThumbs();

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
