import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spotter/app_providers.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/core/settings/app_settings.dart';
import 'package:spotter/core/theme/app_theme.dart';
import 'package:spotter/features/import/data/liftoff_import_service.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/ranks/data/body_map.dart';
import 'package:spotter/features/ranks/domain/body_regions.dart';
import 'package:spotter/features/ranks/presentation/anatomy_graph.dart';
import 'package:spotter/features/readiness/data/readiness_repository.dart';

import 'harness.dart';

/// The owner's Liftoff export on the host (never committed). Without it, a small fixture.
const _realCsv = String.fromEnvironment('LIFTOFF_CSV');

String _fixture() {
  String d(int daysAgo) {
    final t = DateTime.now().subtract(Duration(days: daysAgo));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} 08:00:00';
  }

  const dur = '01 hours 00 minutes 00 seconds';
  return 'Date,Duration,Workout Name,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE,Notes\n'
      '${d(10)},$dur,,Chest Press,0,143.3,8,0,0,,6-8\n'
      '${d(10)},$dur,,Machine Chest Fly,0,154.3,12,0,0,,10-12\n'
      '${d(5)},$dur,,Lat Pulldown,0,154.3,8,0,0,,6-8\n'
      '${d(5)},$dur,,EZ Bar Curl,0,88.2,8,0,0,,6-8\n'
      '${d(3)},$dur,,Leg Press,0,400,10,0,0,,8-10\n';
}

/// The most interior point of [m]'s parts (largest clear radius, away from the outlines), not
/// covered by a later-drawn part.
Offset? _pointIn(BodyView view, Muscle m) {
  final parts = view.parts;
  Offset? best;
  var bestR = 0.0;
  for (final (i, part) in parts.indexed) {
    if (part.muscle != m) continue;
    final b = part.path.getBounds();
    bool clear(Offset p) => part.path.contains(p) && !parts.skip(i + 1).any((o) => o.path.contains(p));
    for (var fy = 0.05; fy < 1; fy += 0.05) {
      for (var fx = 0.05; fx < 1; fx += 0.05) {
        final p = Offset(b.left + b.width * fx, b.top + b.height * fy);
        if (!clear(p)) continue;
        var r = 0.5;
        while (r < 40 && [for (var k = 0; k < 8; k++) Offset(p.dx + r * _cos[k], p.dy + r * _sin[k])].every(clear)) {
          r += 0.5;
        }
        if (r > bestR) {
          bestR = r;
          best = p;
        }
      }
    }
  }
  return best;
}

const _cos = [1.0, 0.7071, 0.0, -0.7071, -1.0, -0.7071, 0.0, 0.7071];
const _sin = [0.0, 0.7071, 1.0, 0.7071, 0.0, -0.7071, -1.0, -0.7071];

Offset _toScreen(AppHarness h, BodyView view, Offset local, bool back) {
  final rect = h.tester.getRect(find.byKey(ValueKey(back ? 'body-back' : 'body-front')));
  final b = view.bounds;
  final s = rect.width / b.width < rect.height / b.height ? rect.width / b.width : rect.height / b.height;
  return Offset(rect.left + (rect.width - b.width * s) / 2 + (local.dx - b.left) * s, rect.top + (rect.height - b.height * s) / 2 + (local.dy - b.top) * s);
}

double _dist(Color a, Color b) {
  final dr = (a.r - b.r) * 255, dg = (a.g - b.g) * 255, db = (a.b - b.b) * 255;
  return dr * dr + dg * dg + db * db;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Body map with my real import: computed ranks reach the map and every ranked muscle is painted '
      'in its tier color; tap all 20 muscles; the three modes', (tester) async {
    final h = AppHarness(tester);
    await h.launchFresh();
    await h.onboard(bodyweight: '106');
    await tester.runAsync(() async {
      final db = h.db!;
      if (_realCsv.isNotEmpty) await BodyWeightRepository(db).addManual(108, at: DateTime(2026, 4, 19));
      final catalog = await ExerciseRepository(db).watchCatalog().first;
      final s = LiftoffImportService(db);
      final csv = _realCsv.isNotEmpty ? File(_realCsv).readAsStringSync() : _fixture();
      await s.commit(await s.preview(csv, catalog: catalog), catalog: catalog, settings: const SettingsModel(), now: DateTime.now());
    });
    await h.pumpApp();
    await h.goTab(Icons.insights_outlined);
    await h.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Body')));
    await h.waitFor(find.byKey(const ValueKey('body-front')), scroll: false);
    await h.settle(10);

    debugPrint('STEP 1: the ranks the app computed are the ones the map gets');
    final container = ProviderScope.containerOf(tester.element(find.byType(AnatomyGraph)));
    final summary = container.read(ranksProvider).value!;
    final graph = tester.widget<AnatomyGraph>(find.byType(AnatomyGraph));
    final ranked = {for (final e in summary.muscles.entries) e.key: e.value.score};
    expect(ranked, isNotEmpty, reason: 'the import ranks some muscles');
    for (final m in Muscle.values) {
      expect(graph.scores[m]?.value, ranked[m]?.value, reason: '${m.label}: score reaching the map');
    }

    debugPrint('STEP 2: tier → color for every ranked muscle');
    for (final e in ranked.entries) {
      expect(graph.colorFor(e.key), tierColors[e.value.tier.index], reason: '${e.key.label} (${e.value.label})');
      expect(graph.colorFor(e.key), isNot(AppColors.unranked));
    }
    final tiers = {for (final s in ranked.values) s.tier.label};
    debugPrint('ranked muscles: ${ranked.length}/20, tiers: ${tiers.join(', ')}');

    debugPrint('STEP 3: the pixels: each ranked muscle is drawn in its tier color, not unranked slate');
    final map = (await tester.runAsync(BodyMap.load))!;
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final dpr = tester.view.devicePixelRatio;
    final physical = view.size * dpr;
    late ByteData pixels;
    late int width;
    await tester.runAsync(() async {
      final image = await layer.toImage(Offset.zero & physical, pixelRatio: 1);
      width = image.width;
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    Color pixelAt(Offset logical) {
      final x = (logical.dx * dpr).round(), y = (logical.dy * dpr).round();
      final i = (y * width + x) * 4;
      return Color.fromARGB(255, pixels.getUint8(i), pixels.getUint8(i + 1), pixels.getUint8(i + 2));
    }

    var checked = 0;
    for (final e in ranked.entries) {
      final back = muscleOnBack(e.key);
      final v = back ? map.back : map.front;
      final p = _pointIn(v, e.key) ?? _pointIn(back ? map.front : map.back, e.key);
      if (p == null) continue;
      final onBack = _pointIn(v, e.key) != null ? back : !back;
      final c = pixelAt(_toScreen(h, onBack ? map.back : map.front, p, onBack));
      final tier = tierColors[e.value.tier.index];
      expect(_dist(c, tier), lessThan(_dist(c, AppColors.unranked)),
          reason: '${e.key.label}: pixel $c should be ${e.value.label} ($tier), not unranked');
      expect(_dist(c, tier), lessThan(60 * 60), reason: '${e.key.label}: pixel $c close to ${e.value.label} $tier');
      checked++;
    }
    expect(checked, ranked.length);
    await h.shot('rank');

    debugPrint('STEP 4: tap all 20 muscles across both views');
    final tapped = <Muscle>{};
    for (final back in [false, true]) {
      final v = back ? map.back : map.front;
      for (final m in v.muscles) {
        final p = _pointIn(v, m);
        if (p == null) continue;
        await tester.tapAt(_toScreen(h, v, p, back));
        await tester.pump(const Duration(milliseconds: 120));
        expect(find.byKey(const ValueKey('muscle-callout')), findsOneWidget, reason: 'callout for ${m.label}');
        await h.waitFor(find.descendant(of: find.byType(BottomSheet), matching: find.text(m.label)), reason: '${m.label} sheet', scroll: false);
        tapped.add(m);
        await tester.tapAt(const Offset(20, 80));
        await h.settle(6);
      }
    }
    expect(tapped, Muscle.values.toSet());

    debugPrint('STEP 5: recovery and volume');
    await h.tap(find.byKey(const ValueKey('mode-recovery')));
    await h.waitFor(find.text('Recovering 60–89%'), scroll: false);
    await h.scrollToTop();
    await h.shot('recovery');
    await h.tap(find.byKey(const ValueKey('mode-volume')));
    await h.waitFor(find.text('On track'), scroll: false);
    await h.shot('volume');

    await h.expectNoLoggedErrors();
    await h.dispose();
  });
}
