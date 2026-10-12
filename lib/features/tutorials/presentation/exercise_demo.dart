import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/db/database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/media_repository.dart';
import '../data/video_repository.dart';

final mediaRepositoryProvider = Provider((ref) => MediaRepository(ref.watch(databaseProvider)));
final pinnedVideoRepositoryProvider = Provider((ref) => PinnedVideoRepository(ref.watch(databaseProvider)));

final mediaMatchProvider = StreamProvider.family<MediaMatchRow?, String>(
  (ref, id) => ref.watch(mediaRepositoryProvider).watchMatch(id),
);

final pinnedVideoProvider = StreamProvider.family<PinnedVideo?, String>(
  (ref, id) => ref.watch(pinnedVideoRepositoryProvider).watch(id),
);

/// Decoded GIF frames, cached per URL for the session.
class GifFrames {
  GifFrames(this.frames, this.durations) : total = durations.fold(Duration.zero, (a, b) => a + b);
  final List<ui.Image> frames;
  final List<Duration> durations;
  final Duration total;
}

final gifFramesProvider = FutureProvider.family<GifFrames, String>((ref, url) async {
  final file = await gifCacheManager.getSingleFile(url);
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frames = <ui.Image>[];
  final durations = <Duration>[];
  for (var i = 0; i < codec.frameCount; i++) {
    final f = await codec.getNextFrame();
    frames.add(f.image);
    // Browsers treat ≤ 10 ms as 100 ms; do the same so broken GIFs don't race.
    durations.add(f.duration.inMilliseconds <= 10 ? const Duration(milliseconds: 100) : f.duration);
  }
  codec.dispose();
  ref.onDispose(() {
    for (final f in frames) {
      f.dispose();
    }
  });
  return GifFrames(frames, durations);
});

/// The 3D demonstration for an exercise: the matched ExerciseDB animation, looping, with
/// play/pause and 0.5× speed. Falls back to the library's photos when nothing matched.
class ExerciseDemo extends ConsumerWidget {
  const ExerciseDemo({super.key, required this.exerciseId, this.fallbackImages = const [], this.compact = false});

  final String exerciseId;
  final List<String> fallbackImages;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(mediaMatchProvider(exerciseId));
    final url = match.value?.gifUrl;
    final frame = AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          border: Border.all(color: AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: match.isLoading
            ? const _Skeleton()
            : url == null
                ? _Fallback(images: fallbackImages)
                : _GifPlayer(url: url, compact: compact),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        frame,
        if (url != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '3D demo: ExerciseDB${match.value?.edbName == null ? '' : ' · ${match.value!.edbName}'}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class _GifPlayer extends ConsumerStatefulWidget {
  const _GifPlayer({required this.url, required this.compact});
  final String url;
  final bool compact;

  @override
  ConsumerState<_GifPlayer> createState() => _GifPlayerState();
}

class _GifPlayerState extends ConsumerState<_GifPlayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = true;
  bool _half = false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    if (!_playing) return;
    setState(() => _position += _half ? dt ~/ 2 : dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int _frameAt(GifFrames g) {
    if (g.total == Duration.zero) return 0;
    var t = Duration(microseconds: _position.inMicroseconds % g.total.inMicroseconds);
    for (var i = 0; i < g.durations.length; i++) {
      if (t < g.durations[i]) return i;
      t -= g.durations[i];
    }
    return g.durations.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final gif = ref.watch(gifFramesProvider(widget.url));
    return gif.when(
      loading: () => const _Skeleton(),
      error: (e, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Demo unavailable offline.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ),
      ),
      data: (g) => Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => setState(() => _playing = !_playing),
            child: RawImage(image: g.frames[_frameAt(g)], fit: BoxFit.contain, filterQuality: FilterQuality.medium),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                _Pill(label: _half ? '0.5×' : '1×', active: _half, onTap: () => setState(() => _half = !_half)),
                const SizedBox(width: 8),
                _Pill(
                  icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  onTap: () => setState(() => _playing = !_playing),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({this.label, this.icon, this.active = false, required this.onTap});
  final String? label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.primary : Colors.black.withValues(alpha: 0.65),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          width: 60,
          child: Center(
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 26)
                : Text(label!,
                    style: TextStyle(
                      color: active ? const Color(0xFF06210F) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    )),
          ),
        ),
      ),
    );
  }
}

/// No ExerciseDB match: alternate the library's two photos.
class _Fallback extends StatefulWidget {
  const _Fallback({required this.images});
  final List<String> images;

  @override
  State<_Fallback> createState() => _FallbackState();
}

class _FallbackState extends State<_Fallback> {
  Timer? _t;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    if (widget.images.length > 1) {
      _t = Timer.periodic(const Duration(milliseconds: 1100), (_) => setState(() => _i = (_i + 1) % widget.images.length));
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No 3D demo for this exercise yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: CachedNetworkImage(
            key: ValueKey(_i),
            imageUrl: widget.images[_i],
            fit: BoxFit.contain,
            placeholder: (_, _) => const _Skeleton(),
            errorWidget: (_, _, _) => const Icon(Icons.image_not_supported_outlined, color: Colors.black38),
          ),
        ),
        const Positioned(
          left: 8,
          bottom: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(8))),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('Photos · no 3D demo matched', style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shimmering placeholder.
class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1 + 2 * _c.value - 0.6, 0),
            end: Alignment(-1 + 2 * _c.value + 0.6, 0),
            colors: const [Color(0xFFE9ECF2), Color(0xFFF7F8FB), Color(0xFFE9ECF2)],
          ),
        ),
      ),
    );
  }
}

/// Keeps matches up to date and prefetches demos for every routine exercise.
final mediaBootstrapProvider = FutureProvider<void>((ref) async {
  final catalog = await ref.watch(catalogProvider.future);
  final repo = ref.read(mediaRepositoryProvider);
  await repo.ensureMatched(catalog, now: ref.read(clockProvider)());
  final routines = await ref.watch(routinesProvider.future);
  await repo.prefetch([for (final r in routines) ...r.exercises.map((e) => e.exerciseId)]);
});
