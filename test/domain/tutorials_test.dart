import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/tutorials/domain/media_matcher.dart';
import 'package:spotter/features/tutorials/domain/youtube.dart';

void main() {
  group('YouTube links', () {
    test('all common link shapes, with timestamps', () {
      expect(parseYouTubeLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), const YouTubeRef('dQw4w9WgXcQ'));
      expect(parseYouTubeLink('https://youtu.be/dQw4w9WgXcQ?t=90'), const YouTubeRef('dQw4w9WgXcQ', startSeconds: 90));
      expect(parseYouTubeLink('youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s'), const YouTubeRef('dQw4w9WgXcQ', startSeconds: 90));
      expect(parseYouTubeLink('https://m.youtube.com/shorts/dQw4w9WgXcQ'), const YouTubeRef('dQw4w9WgXcQ'));
      expect(parseYouTubeLink('https://www.youtube.com/embed/dQw4w9WgXcQ?start=12'), const YouTubeRef('dQw4w9WgXcQ', startSeconds: 12));
      expect(parseYouTubeLink('dQw4w9WgXcQ'), const YouTubeRef('dQw4w9WgXcQ'));
    });

    test('rejects non-YouTube input', () {
      expect(parseYouTubeLink('https://vimeo.com/123'), isNull);
      expect(parseYouTubeLink('https://youtube.com/watch?v=short'), isNull);
      expect(parseYouTubeLink('bench press'), isNull);
    });

    test('timestamps', () {
      expect(parseTimestamp('90'), 90);
      expect(parseTimestamp('90s'), 90);
      expect(parseTimestamp('1m30s'), 90);
      expect(parseTimestamp('1h2m3s'), 3723);
      expect(parseTimestamp('1:30'), 90);
      expect(parseTimestamp('1:02:03'), 3723);
      expect(parseTimestamp('soon'), isNull);
      expect(formatTimestamp(90), '1:30');
      expect(formatTimestamp(3723), '1:02:03');
    });
  });

  group('media matcher', () {
    final edb = ((jsonDecode(File('assets/exercisedb_v1.json').readAsStringSync()) as Map<String, dynamic>)['exercises']
            as List<dynamic>)
        .map((e) => EdbExercise.fromJson(e as Map<String, dynamic>))
        .toList();
    final lib = {
      for (final e in (jsonDecode(File('assets/exercises.json').readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>())
        e['id'] as String: LibraryExerciseKey(
          id: e['id'] as String,
          name: e['name'] as String,
          equipment: e['equipment'] as String?,
          primaryMuscles: (e['primaryMuscles'] as List<dynamic>).cast<String>(),
          secondaryMuscles: (e['secondaryMuscles'] as List<dynamic>).cast<String>(),
        ),
    };
    final matcher = MediaMatcher(edb);

    test('normalisation', () {
      expect(MediaMatcher.normalizeTokens('Pullups'), ['pull', 'up']);
      expect(MediaMatcher.normalizeTokens('Barbell Bench Press - Medium Grip'), ['barbell', 'bench', 'press']);
      expect(MediaMatcher.normalizeTokens('Dumbbell Flyes'), ['dumbbell', 'fly']);
      expect(MediaMatcher.normalizeTokens('Standing Military Press'), ['standing', 'shoulder', 'press']);
    });

    test('key lifts match the right animation with high confidence', () {
      const expected = {
        'Barbell_Bench_Press_-_Medium_Grip': 'barbell bench press',
        'Pullups': 'pull-up',
        'Barbell_Deadlift': 'barbell deadlift',
        'Dumbbell_Bench_Press': 'dumbbell bench press',
        'Barbell_Curl': 'barbell curl',
        'Bent_Over_Barbell_Row': 'barbell bent over row',
        'Seated_Cable_Rows': 'cable seated row',
        'Dips_-_Triceps_Version': 'triceps dip',
        'Front_Barbell_Squat': 'barbell front squat',
      };
      for (final e in expected.entries) {
        final m = matcher.match(lib[e.key]!);
        expect(m.best!.edb.name.toLowerCase(), e.value, reason: e.key);
        expect(m.confidence, MatchConfidence.high, reason: e.key);
      }
    });

    test('equipment and muscle scoring', () {
      expect(MediaMatcher.equipmentScore('dumbbell', ['dumbbell']), 1);
      expect(MediaMatcher.equipmentScore('dumbbell', ['dumbbell', 'stability ball']), 0.6);
      expect(MediaMatcher.equipmentScore('barbell', ['dumbbell']), 0);
      expect(MediaMatcher.equipmentScore('other', ['dumbbell']), 0.5);
      expect(MediaMatcher.muscleScore(['chest'], ['pectorals']), 1);
      expect(MediaMatcher.muscleScore(['quadriceps'], ['glutes'], ['glutes']), 0.7);
      expect(MediaMatcher.muscleScore(['chest'], ['biceps']), 0);
      expect(MediaMatcher.muscleScore(['lower back'], ['erector spinae']), 1);
    });

    test('most of the library gets a usable demo', () {
      var usable = 0;
      for (final k in lib.values) {
        if (matcher.match(k).confidence != MatchConfidence.none) usable++;
      }
      expect(usable / lib.length, greaterThan(0.85));
    });
  });
}
