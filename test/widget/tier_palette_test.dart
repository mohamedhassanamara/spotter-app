import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/theme/app_theme.dart';
import 'package:spotter/features/ranks/domain/ranks.dart';

/// WCAG 2 contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double hueDistance(Color a, Color b) {
  final d = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
  return math.min(d, 360 - d);
}

void main() {
  test('one color per tier', () => expect(tierColors.length, Tier.values.length));

  test('every tier color has WCAG contrast ≥ 3:1 against the body fill', () {
    for (final (i, c) in tierColors.indexed) {
      expect(contrast(c, AppColors.unranked), greaterThanOrEqualTo(3), reason: Tier.values[i].name);
    }
  });

  test('saturated, and no two tiers share a hue family (≥ 24° apart)', () {
    for (final (i, c) in tierColors.indexed) {
      expect(HSLColor.fromColor(c).saturation, greaterThanOrEqualTo(0.6), reason: Tier.values[i].name);
      for (var j = i + 1; j < tierColors.length; j++) {
        expect(hueDistance(c, tierColors[j]), greaterThanOrEqualTo(24), reason: '${Tier.values[i].name} vs ${Tier.values[j].name}');
      }
    }
  });

  test('adjacent tiers are far apart in hue (≥ 25°)', () {
    for (var i = 0; i + 1 < tierColors.length; i++) {
      expect(hueDistance(tierColors[i], tierColors[i + 1]), greaterThanOrEqualTo(25), reason: '${Tier.values[i].name} → ${Tier.values[i + 1].name}');
    }
  });

  test('the body fill is a dark neutral', () {
    final hsl = HSLColor.fromColor(AppColors.unranked);
    expect(hsl.lightness, lessThan(0.2));
    expect(hsl.saturation, lessThan(0.25));
  });
}
