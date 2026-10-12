import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/program_repository.dart';
import '../domain/program_videos.dart';

/// Exercise id → Jeff Nippard's demo, for everything in my Min-Max program (routines and the
/// program's listed substitutions), from the PDF's own links.
final programVideosProvider = FutureProvider<Map<String, ProgramVideo>>((ref) async {
  final program = await ref.watch(programProvider.future);
  final routines = await ref.watch(routinesProvider.future);
  final catalog = await ref.watch(catalogProvider.future);
  return programVideos(
    program: program,
    catalog: catalog,
    rows: [
      for (final r in routines)
        for (final e in r.exercises)
          RoutineVideoRow(
            exerciseId: e.exerciseId,
            name: e.displayName ?? catalog[e.exerciseId]?.name ?? e.exerciseId,
            relation: e.programRelation,
            programExercise: e.programExercise,
            slotIds: decodeSlots(e.programSlots),
          ),
    ],
  );
});

/// Jeff's demo embedded in the app: no autoplay, opening at the link's timestamp.
class ProgramVideoPlayer extends StatefulWidget {
  const ProgramVideoPlayer({super.key, required this.video});
  final ProgramVideo video;

  @override
  State<ProgramVideoPlayer> createState() => _ProgramVideoPlayerState();
}

class _ProgramVideoPlayerState extends State<ProgramVideoPlayer> {
  late final YoutubePlayerController _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.video.ref.videoId,
    startSeconds: widget.video.ref.startSeconds.toDouble(),
    autoPlay: false,
    params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true, playsInline: true),
  );

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: YoutubePlayer(key: const ValueKey('program-video'), controller: _controller),
      ),
      const SizedBox(height: 6),
      Text(
        'Demo: Jeff Nippard · ${widget.video.programName} (Min-Max Program)',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ]);
  }
}
