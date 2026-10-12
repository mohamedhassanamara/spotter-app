import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../data/video_repository.dart';
import '../domain/youtube.dart';
import 'exercise_demo.dart';

final youtubeKeyStoreProvider = Provider((ref) => YouTubeKeyStore());

/// Whether a YouTube Data API key is set (Keychain). Invalidate after changing it.
final youtubeKeyProvider = FutureProvider<String?>((ref) => ref.watch(youtubeKeyStoreProvider).read());

final youtubeSearchProvider = FutureProvider.family<List<VideoResult>, String>((ref, exerciseName) async {
  final key = await ref.watch(youtubeKeyProvider.future);
  if (key == null) return const [];
  return YouTubeSearchClient(key).search(YouTubeSearchClient.queryFor(exerciseName));
});

/// Video tab: the pinned tutorial plays in-app; otherwise find one (API search or a pasted link).
class TutorialVideoTab extends ConsumerWidget {
  const TutorialVideoTab({super.key, required this.exerciseId, required this.exerciseName, required this.searchUri});

  final String exerciseId;
  final String exerciseName;
  final Uri searchUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedVideoProvider(exerciseId));
    return pinned.when(
      loading: () => const SizedBox(height: 200),
      error: (e, _) => Text('$e'),
      data: (p) => p == null
          ? _Finder(exerciseId: exerciseId, exerciseName: exerciseName, searchUri: searchUri)
          : _PinnedPlayer(key: ValueKey('${p.videoId}@${p.startSeconds}'), pinned: p, exerciseName: exerciseName),
    );
  }
}

class _PinnedPlayer extends ConsumerStatefulWidget {
  const _PinnedPlayer({super.key, required this.pinned, required this.exerciseName});
  final PinnedVideo pinned;
  final String exerciseName;

  @override
  ConsumerState<_PinnedPlayer> createState() => _PinnedPlayerState();
}

class _PinnedPlayerState extends ConsumerState<_PinnedPlayer> {
  late final YoutubePlayerController _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.pinned.videoId,
    startSeconds: widget.pinned.startSeconds.toDouble(),
    params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true, playsInline: true),
  );

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pinned;
    final repo = ref.read(pinnedVideoRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(16), child: YoutubePlayer(controller: _controller)),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.push_pin_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              p.title.isEmpty ? 'Pinned tutorial' : p.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        if (p.channel.isNotEmpty) Text(p.channel, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.timer_outlined),
              label: Text(p.startSeconds == 0 ? 'Set start time' : 'Starts at ${formatTimestamp(p.startSeconds)}'),
              onPressed: () async {
                final current = (await _controller.currentTime).round();
                if (!context.mounted) return;
                final raw = await promptText(
                  context,
                  title: 'Start at',
                  initial: formatTimestamp(current > 0 ? current : p.startSeconds),
                  hint: '1:30, 90 or 1m30s',
                );
                final s = raw == null ? null : parseTimestamp(raw);
                if (s != null) await repo.setStart(p.exerciseId, s);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open in YouTube'),
              onPressed: () => launchUrl(YouTubeRef(p.videoId, startSeconds: p.startSeconds).watchUri,
                  mode: LaunchMode.externalApplication),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              icon: const Icon(Icons.push_pin_outlined),
              label: const Text('Unpin'),
              onPressed: () => repo.unpin(p.exerciseId),
            ),
          ],
        ),
      ],
    );
  }
}

class _Finder extends ConsumerStatefulWidget {
  const _Finder({required this.exerciseId, required this.exerciseName, required this.searchUri});
  final String exerciseId;
  final String exerciseName;
  final Uri searchUri;

  @override
  ConsumerState<_Finder> createState() => _FinderState();
}

class _FinderState extends ConsumerState<_Finder> {
  final _link = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pin(YouTubeRef ref0, {String title = '', String channel = ''}) async {
    await ref.read(pinnedVideoRepositoryProvider).pin(widget.exerciseId, ref0,
        title: title, channel: channel, now: ref.read(clockProvider)());
    HapticFeedback.mediumImpact();
  }

  Future<void> _pinPasted() async {
    final parsed = parseYouTubeLink(_link.text);
    if (parsed == null) {
      setState(() => _error = 'That doesn\'t look like a YouTube link.');
      return;
    }
    setState(() => _error = null);
    await _pin(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(youtubeKeyProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Pin a tutorial', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          key == null
              ? 'Paste a YouTube link (a timestamp like ?t=90 is kept). Add a YouTube Data API key in Settings to search here.'
              : 'Tap a result to pin it. It plays right here between sets.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (key != null) _Results(name: widget.exerciseName, onPick: (v) => _pin(YouTubeRef(v.videoId), title: v.title, channel: v.channel)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(hintText: 'https://youtu.be/…', errorText: _error),
              onSubmitted: (_) => _pinPasted(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Paste',
            style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) setState(() => _link.text = data!.text!);
            },
            icon: const Icon(Icons.content_paste_rounded),
          ),
        ]),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _pinPasted, icon: const Icon(Icons.push_pin_rounded), label: const Text('Pin link')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => launchUrl(widget.searchUri, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.search_rounded),
          label: const Text('Search in YouTube'),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.name, required this.onPick});
  final String name;
  final ValueChanged<VideoResult> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(youtubeSearchProvider(name));
    return results.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.danger)),
      data: (list) => Column(
        children: [
          for (final v in list)
            InkWell(
              onTap: () => onPick(v),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(imageUrl: v.thumbnailUrl, width: 128, height: 72, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(v.channel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                    const Icon(Icons.push_pin_outlined, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
