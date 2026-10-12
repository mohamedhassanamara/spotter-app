import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/tutorials/data/media_repository.dart';
import 'package:spotter/features/tutorials/data/video_repository.dart';
import 'package:spotter/features/tutorials/domain/youtube.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('matching: overrides applied, manual picks survive re-matching, export format', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ex = ExerciseRepository(db);
    await ex.ensureSeeded(jsonOverride: File('assets/exercises.json').readAsStringSync());
    final catalog = await ex.watchCatalog().first;
    final repo = MediaRepository(db);
    final now = DateTime(2026, 10, 12);

    await repo.ensureMatched(catalog, now: now);
    final rows = await db.select(db.mediaMatches).get();
    expect(rows.length, catalog.length);

    final squat = (await repo.match('Barbell_Squat'))!;
    expect(squat.source, 'override');
    expect(squat.edbId, 'qXTaZnJ');
    expect(squat.gifUrl, startsWith('https://static.exercisedb.dev/media/'));
    final face = (await repo.match('Face_Pull'))!;
    expect(face.source, 'override');
    expect(face.edbId, isNull, reason: 'null override = no demo');
    expect((await repo.match('Barbell_Curl'))!.source, 'auto');

    // Manual pick, then force a re-match (version bump): the pick is kept.
    final edb = await MediaRepository.loadEdb();
    await repo.setManual('Barbell_Curl', edb.firstWhere((e) => e.id == 'EIeI8Vf'), now: now);
    await db.putSetting('media_match_version', '0');
    await repo.ensureMatched(catalog, now: now);
    expect((await repo.match('Barbell_Curl'))!.edbId, 'EIeI8Vf');
    expect((await repo.match('Barbell_Curl'))!.source, 'manual');

    final exported = jsonDecode(await repo.exportOverrides()) as Map<String, dynamic>;
    expect(exported['schema_version'], 1);
    final o = exported['overrides'] as Map<String, dynamic>;
    expect(o['Barbell_Curl'], 'EIeI8Vf');
    expect(o.containsKey('Face_Pull'), isTrue);
    expect(o['Face_Pull'], isNull);
  });

  test('pinned videos: pin, change start, unpin', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = PinnedVideoRepository(db);
    await repo.pin('Pullups', const YouTubeRef('dQw4w9WgXcQ', startSeconds: 30), title: 'Pull-up form', now: DateTime(2026));
    expect((await repo.get('Pullups'))!.startSeconds, 30);
    await repo.setStart('Pullups', 95);
    expect((await repo.get('Pullups'))!.startSeconds, 95);
    await repo.pin('Pullups', const YouTubeRef('aaaaaaaaaaa'), now: DateTime(2026));
    expect((await repo.get('Pullups'))!.videoId, 'aaaaaaaaaaa');
    await repo.unpin('Pullups');
    expect(await repo.get('Pullups'), isNull);
  });

  test('YouTube search parses results and surfaces API errors', () async {
    late Uri seen;
    final ok = MockClient((req) async {
      seen = req.url;
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': {'kind': 'youtube#video', 'videoId': 'dQw4w9WgXcQ'},
              'snippet': {
                'title': 'Bench Press &amp; Form',
                'channelTitle': 'Coach',
                'thumbnails': {'medium': {'url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg'}},
              },
            },
            {'id': {'kind': 'youtube#channel', 'channelId': 'x'}, 'snippet': {'title': 'skip'}},
          ],
        }),
        200,
      );
    });
    final results = await YouTubeSearchClient('KEY', client: ok).search(YouTubeSearchClient.queryFor('Bench Press'));
    expect(results.single.title, 'Bench Press & Form');
    expect(seen.queryParameters['q'], 'Bench Press proper form');
    expect(seen.queryParameters['key'], 'KEY');

    final bad = MockClient((_) async => http.Response(jsonEncode({'error': {'message': 'API key not valid. <b>x</b>'}}), 400));
    expect(
      () => YouTubeSearchClient('KEY', client: bad).search('x'),
      throwsA(isA<YouTubeSearchException>().having((e) => e.message, 'message', contains('API key not valid. x'))),
    );
  });
}
