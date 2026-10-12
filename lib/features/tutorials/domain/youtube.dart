/// A YouTube video reference with an optional start time.
class YouTubeRef {
  const YouTubeRef(this.videoId, {this.startSeconds = 0});
  final String videoId;
  final int startSeconds;

  Uri get watchUri => Uri.https('www.youtube.com', '/watch', {
        'v': videoId,
        if (startSeconds > 0) 't': '${startSeconds}s',
      });

  Uri get thumbnailUri => Uri.https('i.ytimg.com', '/vi/$videoId/hqdefault.jpg');

  @override
  bool operator ==(Object other) => other is YouTubeRef && other.videoId == videoId && other.startSeconds == startSeconds;

  @override
  int get hashCode => Object.hash(videoId, startSeconds);
}

final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Parses watch, youtu.be, shorts, embed, live and m. links (and bare 11-char ids), including
/// `t=` / `start=` timestamps like `90`, `90s`, `1m30s`, `1h2m3s`. Returns null when it isn't YouTube.
YouTubeRef? parseYouTubeLink(String input) {
  final text = input.trim();
  if (_id.hasMatch(text)) return YouTubeRef(text);
  final uri = Uri.tryParse(text.startsWith('http') ? text : 'https://$text');
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m|music)\.'), '');
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
    final seg = uri.pathSegments;
    if (seg.isNotEmpty && seg.first == 'watch') {
      id = uri.queryParameters['v'];
    } else if (seg.length >= 2 && const {'shorts', 'embed', 'live', 'v'}.contains(seg.first)) {
      id = seg[1];
    }
  }
  if (id == null || !_id.hasMatch(id)) return null;
  final t = uri.queryParameters['t'] ?? uri.queryParameters['start'];
  return YouTubeRef(id, startSeconds: t == null ? 0 : (parseTimestamp(t) ?? 0));
}

/// `90`, `90s`, `1m30s`, `1h2m3s`, `1:30`, `1:02:03` → seconds.
int? parseTimestamp(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(s)) return int.parse(s);
  if (RegExp(r'^\d+(:\d{1,2}){1,2}$').hasMatch(s)) {
    return s.split(':').fold<int>(0, (acc, p) => acc * 60 + int.parse(p));
  }
  final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(s);
  if (m == null || m.group(0)!.isEmpty) return null;
  int part(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  return part(1) * 3600 + part(2) * 60 + part(3);
}

String formatTimestamp(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
