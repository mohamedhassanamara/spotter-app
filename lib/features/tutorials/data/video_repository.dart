import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/db/database.dart';
import '../domain/youtube.dart';

class PinnedVideoRepository {
  PinnedVideoRepository(this._db);
  final AppDatabase _db;

  Stream<PinnedVideo?> watch(String exerciseId) =>
      (_db.select(_db.pinnedVideos)..where((t) => t.exerciseId.equals(exerciseId))).watchSingleOrNull();

  Future<PinnedVideo?> get(String exerciseId) =>
      (_db.select(_db.pinnedVideos)..where((t) => t.exerciseId.equals(exerciseId))).getSingleOrNull();

  Future<void> pin(String exerciseId, YouTubeRef ref, {String title = '', String channel = '', required DateTime now}) {
    final row = PinnedVideosCompanion.insert(
      exerciseId: exerciseId,
      videoId: ref.videoId,
      title: Value(title),
      channel: Value(channel),
      startSeconds: Value(ref.startSeconds),
      pinnedAt: now,
    );
    return _db.into(_db.pinnedVideos).insert(row, onConflict: DoUpdate((_) => row));
  }

  Future<void> setStart(String exerciseId, int seconds) =>
      (_db.update(_db.pinnedVideos)..where((t) => t.exerciseId.equals(exerciseId)))
          .write(PinnedVideosCompanion(startSeconds: Value(seconds)));

  Future<void> unpin(String exerciseId) => (_db.delete(_db.pinnedVideos)..where((t) => t.exerciseId.equals(exerciseId))).go();
}

/// The optional YouTube Data API key, kept in the iOS Keychain.
class YouTubeKeyStore {
  YouTubeKeyStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  static const _key = 'youtube_data_api_key';

  Future<String?> read() async {
    final v = await _storage.read(key: _key);
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  Future<void> write(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: value.trim());
    }
  }
}

class VideoResult {
  const VideoResult({required this.videoId, required this.title, required this.channel, required this.thumbnailUrl});
  final String videoId;
  final String title;
  final String channel;
  final String thumbnailUrl;
}

class YouTubeSearchException implements Exception {
  YouTubeSearchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// YouTube Data API v3 search (only used when the user set a key).
class YouTubeSearchClient {
  YouTubeSearchClient(this.apiKey, {http.Client? client}) : _client = client ?? http.Client();
  final String apiKey;
  final http.Client _client;

  static String queryFor(String exerciseName) => '$exerciseName proper form';

  Future<List<VideoResult>> search(String query, {int max = 12}) async {
    final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
      'part': 'snippet',
      'type': 'video',
      'videoEmbeddable': 'true',
      'maxResults': '$max',
      'q': query,
      'key': apiKey,
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final msg = ((body['error'] as Map<String, dynamic>?)?['message'] as String?) ?? 'HTTP ${res.statusCode}';
      throw YouTubeSearchException('YouTube search failed: ${_strip(msg)}');
    }
    return [
      for (final item in (body['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
        if ((item['id'] as Map<String, dynamic>?)?['videoId'] case final String id)
          VideoResult(
            videoId: id,
            title: _unescape(((item['snippet'] as Map<String, dynamic>)['title'] as String?) ?? ''),
            channel: _unescape(((item['snippet'] as Map<String, dynamic>)['channelTitle'] as String?) ?? ''),
            thumbnailUrl: (((((item['snippet'] as Map<String, dynamic>)['thumbnails'] as Map<String, dynamic>?)?['medium']
                        as Map<String, dynamic>?)?['url']) as String?) ??
                YouTubeRef(id).thumbnailUri.toString(),
          ),
    ];
  }

  static String _strip(String html) => html.replaceAll(RegExp(r'<[^>]+>'), '');

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
