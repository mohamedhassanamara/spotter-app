import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/muscle_group.dart';
import 'package:spotter/features/ranks/data/body_map.dart';
import 'package:spotter/features/ranks/domain/body_regions.dart';
import 'package:spotter/features/readiness/domain/readiness.dart';

void main() {
  final raw = File('assets/body_map.json').readAsStringSync();

  test('every body-map slug is classified and every ranking group is drawable', () {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final slugs = {
      for (final v in ['front', 'back'])
        for (final p in (j[v] as List<dynamic>).cast<Map<String, dynamic>>()) p['slug'] as String,
    };
    const structure = {'head', 'hair', 'hands', 'feet', 'knees', 'ankles'};
    for (final s in slugs) {
      expect(bodySlugToGroup.containsKey(s) || neutralBodySlugs.contains(s) || structure.contains(s), isTrue, reason: s);
    }
    expect(bodySlugToGroup.values.toSet(), MuscleGroup.values.toSet());
    expect(roleForSlug('adductors'), RegionRole.neutral);
    expect(roleForSlug('lower-back'), RegionRole.neutral);
    expect(roleForSlug('neck'), RegionRole.neutral);
    expect(roleForSlug('upper-back'), RegionRole.muscle);
  });

  test('paths parse into non-empty regions for both views', () {
    final m = BodyMap.parse(raw);
    for (final v in [m.front, m.back]) {
      expect(v.regions, isNotEmpty);
      expect(v.bounds.width, greaterThan(100));
      expect(v.regions.every((r) => !r.path.getBounds().isEmpty), isTrue);
    }
    final frontGroups = m.front.regions.map((r) => r.group).whereType<MuscleGroup>().toSet();
    final backGroups = m.back.regions.map((r) => r.group).whereType<MuscleGroup>().toSet();
    expect(frontGroups.union(backGroups), MuscleGroup.values.toSet());
    expect(backGroups, containsAll([MuscleGroup.back, MuscleGroup.glutes, MuscleGroup.hamstrings]));
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
        GroupSetEntry(date: DateTime(2026, 3, 19), groups: {MuscleGroup.back}, sets: 6),
        GroupSetEntry(date: DateTime(2026, 3, 14), groups: {MuscleGroup.back}, sets: 4), // 6 days ago: recent
        GroupSetEntry(date: DateTime(2026, 3, 13), groups: {MuscleGroup.back}, sets: 12), // 7 days ago: prior
        GroupSetEntry(date: DateTime(2026, 2, 20), groups: {MuscleGroup.back, MuscleGroup.biceps}, sets: 8),
        GroupSetEntry(date: DateTime(2026, 2, 10), groups: {MuscleGroup.back}, sets: 50), // too old
      ];
      final c = const TrainingLoad().counts(today, entries);
      expect(c[MuscleGroup.back], (10, 5.0)); // (12 + 8) / 4
      expect(c[MuscleGroup.biceps], (0, 2.0));
      expect(c[MuscleGroup.chest], (0, 0.0));
    });
  });
}
