import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';
import 'package:spotter/features/ranks/presentation/rank_badge.dart';

Future<Uint8List> _render(Tier tier, int division) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  EmblemPainter(tier: tier, division: division).paint(canvas, const Size(240, 260));
  final image = await rec.endRecording().toImage(240, 260);
  return (await image.toByteData())!.buffer.asUint8List();
}

/// Pixels that differ between two renders in the crystal itself (the division marks under it, y > 225, are left out).
int _crystalDiff(Uint8List a, Uint8List b) {
  var n = 0;
  for (var y = 0; y < 225; y++) {
    for (var x = 0; x < 240; x++) {
      final i = (y * 240 + x) * 4;
      final d = (a[i] - b[i]).abs() + (a[i + 1] - b[i + 1]).abs() + (a[i + 2] - b[i + 2]).abs() + (a[i + 3] - b[i + 3]).abs();
      if (d > 24) n++;
    }
  }
  return n;
}

void main() {
  testWidgets('each division of every tier adds visible detail to the emblem itself, not just a pip', (tester) async {
    await tester.runAsync(() async {
      for (final t in Tier.values.where((t) => !t.isApex)) {
        final d1 = await _render(t, 1), d2 = await _render(t, 2), d3 = await _render(t, 3);
        final a = _crystalDiff(d1, d2), b = _crystalDiff(d2, d3);
        expect(a, greaterThan(150), reason: '${t.label}: division 2 differs from 1 in the crystal ($a px)');
        expect(b, greaterThan(150), reason: '${t.label}: division 3 differs from 2 in the crystal ($b px)');
        expect(_crystalDiff(d1, d3), greaterThan(a), reason: '${t.label}: 3 is further from 1 than 2 is');
      }
    });
  });

  testWidgets('the tier stays recognizable across divisions: the mean hue of each tier is the same in all three', (tester) async {
    await tester.runAsync(() async {
      for (final t in Tier.values.where((t) => !t.isApex)) {
        Future<(double, double, double)> mean(int d) async {
          final px = await _render(t, d);
          double r = 0, g = 0, b = 0, n = 0;
          for (var i = 0; i < px.length; i += 4) {
            if (px[i + 3] < 200) continue;
            r += px[i];
            g += px[i + 1];
            b += px[i + 2];
            n++;
          }
          return (r / n, g / n, b / n);
        }

        final m1 = await mean(1), m3 = await mean(3);
        final h1 = HSLColor.fromColor(Color.fromARGB(255, m1.$1.round(), m1.$2.round(), m1.$3.round()));
        final h3 = HSLColor.fromColor(Color.fromARGB(255, m3.$1.round(), m3.$2.round(), m3.$3.round()));
        if (h1.saturation > 0.12) {
          final dh = (h1.hue - h3.hue).abs();
          expect(dh > 180 ? 360 - dh : dh, lessThan(15), reason: '${t.label}: same hue in division 1 and 3');
        }
        expect((h1.lightness - h3.lightness).abs(), lessThan(0.2), reason: '${t.label}: similar lightness');
      }
    });
  });
}
