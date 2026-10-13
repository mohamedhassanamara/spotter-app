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
  test('one color per tier: the original v2 palette', () {
    expect(tierColors.length, Tier.values.length);
    expect(tierColors[Tier.silver.index], const Color(0xFFB9C6D3));
    expect(tierColors[Tier.grandmaster.index], const Color(0xFFFF5A6E));
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
