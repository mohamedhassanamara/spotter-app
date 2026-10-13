import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tutorials/data/media_repository.dart';
import '../../tutorials/presentation/exercise_demo.dart';
import '../../ranks/presentation/anatomy_graph.dart' show ExerciseMuscleThumb;
import '../domain/exercise_info.dart';

/// First frame of a GIF as a still image (thumbnails never animate). Cached per URL for the session.
final gifFirstFrameProvider = FutureProvider.family<ui.Image, String>((ref, url) async {
  final file = await gifCacheManager.getSingleFile(url);
  final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: 200);
  final frame = await codec.getNextFrame();
  codec.dispose();
  ref.onDispose(frame.image.dispose);
  return frame.image;
});

/// flutter test has no disk cache (no path_provider / sqflite): use the in-memory image cache there.
final bool _inTests = Platform.environment.containsKey('FLUTTER_TEST');

IconData equipmentIcon(String? equipment) => switch (equipment?.toLowerCase()) {
      'barbell' || 'e-z curl bar' => Icons.fitness_center_rounded,
      'dumbbell' || 'kettlebells' => Icons.fitness_center_rounded,
      'cable' => Icons.cable_rounded,
      'machine' => Icons.precision_manufacturing_rounded,
      'bands' => Icons.gesture_rounded,
      'body only' => Icons.accessibility_new_rounded,
      _ => Icons.sports_gymnastics_rounded,
    };

/// Square, static exercise thumbnail in the 3D-render style only: a still frame of the ExerciseDB GIF,
/// else a generated thumbnail (body silhouette with the exercise's main muscles lit). Never a photo of
/// a real person (photos live in the exercise page's Photos section), never a YouTube image, never animated.
class ExerciseThumb extends ConsumerWidget {
  const ExerciseThumb({super.key, required this.exercise, this.size = 56, this.radius = 12});
  final ExerciseInfo exercise;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generated = ExerciseMuscleThumb(key: ValueKey('thumb-generated-${exercise.id}'), targets: exercise.targets, size: size);
    Widget still(Widget child) => Container(key: ValueKey('thumb-gif-${exercise.id}'), width: size, height: size, color: Colors.white, child: child);
    final gif = ref.watch(mediaMatchProvider(exercise.id)).value?.gifUrl;
    final Widget body = gif == null || _inTests
        ? generated
        : ref.watch(gifFirstFrameProvider(gif)).when(
              data: (img) => still(RawImage(image: img, fit: BoxFit.cover)),
              loading: () => generated,
              error: (_, _) => generated,
            );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox(width: size, height: size, child: body));
  }
}
