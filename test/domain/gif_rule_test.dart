import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/tutorials/domain/gif_rule.dart';
import 'package:spotter/features/tutorials/domain/media_matcher.dart';

void main() {
  final edb = ((jsonDecode(File('assets/exercisedb_v1.json').readAsStringSync()) as Map<String, dynamic>)['exercises'] as List<dynamic>)
      .map((e) => EdbExercise.fromJson(e as Map<String, dynamic>))
      .toList();
  final matcher = MediaMatcher(edb);
  EdbExercise gif(String name) => edb.firstWhere((e) => e.name.toLowerCase() == name.toLowerCase(), orElse: () => fail('no GIF named $name'));
  GifVerdict verdict(String name, String? equipment, String gifName) => gifVerdict(name: name, equipment: equipment, edb: gif(gifName), matcher: matcher);

  group('strict GIF rule: same movement and same equipment, otherwise no GIF', () {
    test('the mismatches found in my routines are refused', () {
      expect(verdict('Dumbbell Walking Lunge', 'dumbbell', 'dumbbell lunge'), GifVerdict.wrongMovement, reason: 'walking vs standing');
      expect(verdict('Dumbbell Walking Lunge', 'dumbbell', 'walking lunge'), GifVerdict.wrongEquipment, reason: 'bodyweight demo');
      expect(verdict('Crunches', 'body only', 'reverse crunch'), GifVerdict.wrongMovement);
      expect(verdict('EZ-Bar Skullcrusher', 'e-z curl bar', 'EZ-Bar Curl'), GifVerdict.wrongMovement, reason: 'a curl is not a skull crusher');
      expect(verdict('T-Bar Row with Handle', 'barbell', 'Machine T Bar Row'), GifVerdict.wrongEquipment);
      expect(verdict('Pendulum Squat', 'machine', 'smith squat'), GifVerdict.wrongMovement);
      expect(verdict('Single-Leg Leg Extension', 'machine', 'Machine Leg Extension'), GifVerdict.wrongMovement, reason: 'one leg vs two');
      expect(verdict('Side Lunge', 'body only', 'lunge with jump'), GifVerdict.wrongMovement);
    });

    test('the same movement on the same equipment passes, whatever the wording', () {
      expect(verdict('Crunches', 'body only', 'crunch floor'), GifVerdict.ok);
      expect(verdict('Butterfly', 'machine', 'Machine Seated Fly'), GifVerdict.ok, reason: 'pec deck / butterfly');
      expect(verdict('Leverage Iso Row', 'machine', 'Machine Seated Row'), GifVerdict.ok);
      expect(verdict('Side Lateral Raise', 'dumbbell', 'dumbbell lateral raise'), GifVerdict.ok, reason: '"side" is part of the name of a lateral raise');
    });

    test('the matcher never offers a candidate that breaks the rule', () {
      final r = matcher.match(const LibraryExerciseKey(id: 'x', name: 'Dumbbell Walking Lunge', equipment: 'dumbbell', primaryMuscles: ['quadriceps']));
      expect(r.candidates, isEmpty);
      final e = matcher.match(const LibraryExerciseKey(id: 'y', name: 'EZ-Bar Skullcrusher', equipment: 'e-z curl bar', primaryMuscles: ['triceps']));
      expect(e.candidates.where((c) => c.edb.name.toLowerCase().contains('curl')), isEmpty);
    });

    test('every override in media_overrides.json obeys the rule', () {
      final overrides = ((jsonDecode(File('assets/media_overrides.json').readAsStringSync()) as Map<String, dynamic>)['overrides'] as Map<String, dynamic>);
      final lib = {
        for (final e in (jsonDecode(File('assets/exercises.json').readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>()) e['id'] as String: e,
      };
      final byId = {for (final e in edb) e.id: e};
      for (final o in overrides.entries) {
        final target = o.value as String?;
        final ex = lib[o.key];
        if (target == null || ex == null) continue;
        expect(gifVerdict(name: ex['name'] as String, equipment: ex['equipment'] as String?, edb: byId[target]!, matcher: matcher), GifVerdict.ok,
            reason: '${ex['name']} → ${byId[target]!.name}');
      }
    });
  });
}
