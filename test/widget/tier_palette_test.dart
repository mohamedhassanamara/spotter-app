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

void main() {
  test('one color per tier: Valorant\'s tier colors (docs/DECISIONS.md)', () {
    expect(tierColors.length, Tier.values.length);
    expect(tierGradients.length, Tier.values.length);
    const hex = {
      Tier.iron: 0xFF868986, Tier.bronze: 0xFFA5855D, Tier.silver: 0xFFBBC2C2, Tier.gold: 0xFFECCF56, Tier.platinum: 0xFF59A9B6,
      Tier.diamond: 0xFFB489C4, Tier.champion: 0xFF6AE2AF, Tier.olympian: 0xFF4F7DFF, Tier.immortal: 0xFFBB3D65,
    };
    for (final t in Tier.values) {
      expect(tierColors[t.index], Color(hex[t]!), reason: t.name);
    }
  });

  test('every tier has a two-colour gradient, a lighter and a deeper shade of its hue', () {
    for (final t in Tier.values) {
      final (light, deep) = tierGradients[t.index];
      expect(light.computeLuminance(), greaterThan(deep.computeLuminance()), reason: '${t.name}: first colour is the lighter one');
      expect(contrast(light, AppColors.bodyBase), greaterThanOrEqualTo(3), reason: '${t.name} light end');
      expect(contrast(deep, AppColors.bodyBase), greaterThanOrEqualTo(2), reason: '${t.name} deep end');
      // Same family: the base colour sits between the two in lightness.
      final base = tierColors[t.index].computeLuminance();
      expect(base, lessThanOrEqualTo(light.computeLuminance() + 1e-6), reason: t.name);
      expect(base, greaterThanOrEqualTo(deep.computeLuminance() - 1e-6), reason: t.name);
    }
  });

  test('every tier color has WCAG contrast ≥ 3:1 against the body map silhouette (bodyBase)', () {
    for (final (i, c) in tierColors.indexed) {
      expect(contrast(c, AppColors.bodyBase), greaterThanOrEqualTo(3), reason: Tier.values[i].name);
    }
  });

  test('unranked is a dark slate: darker than every tier, still distinguishable from the body base', () {
    for (final (i, c) in tierColors.indexed) {
      expect(AppColors.unranked.computeLuminance(), lessThan(c.computeLuminance() / 2), reason: Tier.values[i].name);
    }
    expect(contrast(AppColors.unranked, AppColors.bodyBase), greaterThan(1.2));
    final slate = HSLColor.fromColor(AppColors.unranked);
    expect(slate.lightness, lessThan(0.3));
  });
}
