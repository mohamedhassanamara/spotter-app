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
  test('one color per tier: the League of Legends emblem palette (docs/DECISIONS.md)', () {
    expect(tierColors.length, Tier.values.length);
    const hex = {
      Tier.iron: 0xFFA38887, Tier.bronze: 0xFFBE7F6D, Tier.silver: 0xFF8296BB, Tier.gold: 0xFFC49258, Tier.platinum: 0xFF2295BF,
      Tier.emerald: 0xFF3CD17C, Tier.diamond: 0xFF4280CD, Tier.master: 0xFFAE39E6, Tier.grandmaster: 0xFFEB663E, Tier.challenger: 0xFFB48E52,
    };
    for (final t in Tier.values) {
      expect(tierColors[t.index], Color(hex[t]!), reason: t.name);
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
