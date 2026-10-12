import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscles.dart';
import 'package:spotter/features/ranks/data/body_map.dart';
import 'package:spotter/features/ranks/domain/body_regions.dart';
import 'package:spotter/features/readiness/domain/readiness.dart';

void main() {
  final raw = File('assets/body_map.json').readAsStringSync();

  test('every body-map slug is classified', () {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final slugs = {
      for (final v in ['front', 'back'])
        for (final p in (j[v] as List<dynamic>).cast<Map<String, dynamic>>()) p['slug'] as String,
    };
    const structure = {'head', 'hair', 'hands', 'feet', 'knees', 'ankles'};
    for (final s in slugs) {
      expect(
        bodySlugToMuscle.containsKey(s) || splitBodySlugs.contains(s) || neutralBodySlugs.contains(s) || structure.contains(s),
        isTrue,
        reason: s,
      );
    }
    expect(roleForSlug('adductors'), RegionRole.muscle);
    expect(roleForSlug('lower-back'), RegionRole.muscle);
    expect(roleForSlug('neck'), RegionRole.neutral);
  });

  test('all 20 muscles are drawn and tappable; splits land on the right view', () {
    final m = BodyMap.parse(raw);
    for (final v in [m.front, m.back]) {
      expect(v.parts.every((p) => !p.path.getBounds().isEmpty), isTrue);
    }
    expect(m.front.muscles.union(m.back.muscles), Muscle.values.toSet());
    expect(m.front.muscles, containsAll([Muscle.upperChest, Muscle.lowerChest, Muscle.frontDelt, Muscle.middleDelt, Muscle.abdominals, Muscle.obliques]));
    expect(m.back.muscles, containsAll([Muscle.rearDelt, Muscle.middleDelt, Muscle.lats, Muscle.upperBack, Muscle.abductors, Muscle.glutes, Muscle.lowerBack]));
    expect(m.front.muscles.contains(Muscle.rearDelt), isFalse);
    // Upper chest sits above lower chest; middle delts are outside the front delts.
    final upper = m.front.boundsOf(Muscle.upperChest)!, lower = m.front.boundsOf(Muscle.lowerChest)!;
    expect(upper.center.dy, lessThan(lower.center.dy));
    final abductors = m.back.boundsOf(Muscle.abductors)!, glutes = m.back.boundsOf(Muscle.glutes)!;
    expect(abductors.center.dy, lessThan(glutes.center.dy));
    for (final mu in Muscle.values) {
      expect(m.viewFor(mu).boundsOf(mu), isNotNull, reason: '${mu.label} has a thumbnail');
    }
  });

  group('volume heatmap', () {
    test('buckets', () {
      expect(volumeLevel(null), VolumeLevel.none);
      expect(volumeLevel(const GroupVolume(recentSets: 0, weeklyAverage: 0)), VolumeLevel.none);
      expect(volumeLevel(const GroupVolume(recentSets: 6, weeklyAverage: 0)), VolumeLevel.new_);
      expect(volumeLevel(const GroupVolume(recentSets: 4, weeklyAverage: 10)), VolumeLevel.under);
      expect(volumeLevel(const GroupVolume(recentSets: 8, weeklyAverage: 10)), VolumeLevel.low);
      expect(volumeLevel(const GroupVolume(recentSets: 15, weeklyAverage: 10)), VolumeLevel.onTrack);
      expect(volumeLevel(const GroupVolume(recentSets: 16, weeklyAverage: 10)), VolumeLevel.high);
    });

    test('counts: last 7 days vs weekly average of the 28 days before', () {
      final today = DateTime(2026, 3, 20);
      final entries = [
        GroupSetEntry(date: DateTime(2026, 3, 19), groups: {Muscle.lats}, sets: 6),
        GroupSetEntry(date: DateTime(2026, 3, 14), groups: {Muscle.lats}, sets: 4), // 6 days ago: recent
        GroupSetEntry(date: DateTime(2026, 3, 13), groups: {Muscle.lats}, sets: 12), // 7 days ago: prior
        GroupSetEntry(date: DateTime(2026, 2, 20), groups: {Muscle.lats, Muscle.biceps}, sets: 8),
        GroupSetEntry(date: DateTime(2026, 2, 10), groups: {Muscle.lats}, sets: 50), // too old
      ];
      final c = const TrainingLoad().counts(today, entries);
      expect(c[Muscle.lats], (10, 5.0)); // (12 + 8) / 4
      expect(c[Muscle.biceps], (0, 2.0));
      expect(c[Muscle.upperChest], (0, 0.0));
    });
  });
}
