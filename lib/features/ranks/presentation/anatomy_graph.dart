import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../data/body_map.dart';
import '../domain/body_regions.dart';
import '../domain/ranks.dart';
import 'rank_badge.dart';
import '../../recovery/domain/recovery.dart';

final bodyMapProvider = FutureProvider<BodyMap>((ref) => BodyMap.load());

enum BodyGraphMode {
  ranks('Rank'),
  recovery('Recovery'),
  volume('Volume');

  const BodyGraphMode(this.label);
  final String label;

  static BodyGraphMode fromName(String? n) => values.firstWhere((m) => m.name == n, orElse: () => ranks);
}

/// Colour of a volume heatmap bucket.
Color volumeColor(VolumeLevel level) => switch (level) {
      VolumeLevel.none => AppColors.unranked,
      VolumeLevel.under => const Color(0xFF4C7DFF),
      VolumeLevel.low => const Color(0xFF7FC8FF),
      VolumeLevel.onTrack => AppColors.green,
      VolumeLevel.high => const Color(0xFFFF7A45),
      VolumeLevel.new_ => const Color(0xFFFFC145),
    };

String volumeLabel(VolumeLevel level) => switch (level) {
      VolumeLevel.none => 'Not trained',
      VolumeLevel.under => 'Under-trained',
      VolumeLevel.low => 'Below usual',
      VolumeLevel.onTrack => 'On track',
      VolumeLevel.high => 'Above 1.5×',
      VolumeLevel.new_ => 'New this week',
    };

Color recoveryColor(RecoveryBand? band) => switch (band) {
      RecoveryBand.ready => AppColors.green,
      RecoveryBand.recovering => AppColors.yellow,
      RecoveryBand.fatigued => AppColors.red,
      null => AppColors.unranked,
    };

/// Front and back side by side (no flipping), as large as the width allows: flat muscle shapes filled
/// by tier (Rank), recovery band (Recovery) or last-7-days volume (Volume), separated by a dark gap.
/// Tapping a muscle glows its outline and shows a small callout ([callout]) above it.
class AnatomyGraph extends ConsumerWidget {
  const AnatomyGraph({
    super.key,
    required this.mode,
    required this.scores,
    required this.volume,
    this.recovery,
    required this.onTap,
    this.selected,
    this.selectedOnBack = false,
    this.callout,
  });

  final BodyGraphMode mode;
  final Map<Muscle, RankScore?> scores;
  final Map<Muscle, GroupVolume> volume;
  final RecoveryState? recovery;
  final Muscle? selected;

  /// Which figure the selected muscle was tapped on (where the callout goes).
  final bool selectedOnBack;

  /// Shown above the selected muscle while it's selected.
  final Widget? callout;
  final void Function(Muscle muscle, bool back) onTap;

  Color colorFor(Muscle m) => switch (mode) {
        BodyGraphMode.ranks => scores[m] == null ? AppColors.unranked : tierColors[scores[m]!.tier.index],
        BodyGraphMode.volume => volumeLevel(volume[m]) == VolumeLevel.none ? AppColors.unranked : volumeColor(volumeLevel(volume[m])),
        BodyGraphMode.recovery => recoveryColor(recovery?.of(m).band),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(bodyMapProvider);
    return map.when(
      loading: () => const AspectRatio(aspectRatio: 1, child: SizedBox()),
      error: (e, _) => Text('Body map failed to load: $e'),
      data: (m) {
        final label = AppType.label.copyWith(fontSize: 11, color: AppColors.textTertiary, letterSpacing: 2);
        Widget side(BodyView v, bool back) => Expanded(
              child: Column(children: [
                _ViewCanvas(
                  key: ValueKey(back ? 'body-back' : 'body-front'),
                  view: v,
                  color: colorFor,
                  selected: selected,
                  callout: selected != null && selectedOnBack == back ? callout : null,
                  onTap: (muscle) => onTap(muscle, back),
                ),
                const SizedBox(height: 4),
                Text(back ? 'BACK' : 'FRONT', style: label),
              ]),
            );
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [side(m.front, false), const SizedBox(width: 4), side(m.back, true)]);
      },
    );
  }
}

class _ViewCanvas extends StatelessWidget {
  const _ViewCanvas({super.key, required this.view, required this.color, required this.selected, required this.onTap, this.callout});

  final BodyView view;
  final Color Function(Muscle) color;
  final Muscle? selected;
  final ValueChanged<Muscle> onTap;
  final Widget? callout;

  @override
  Widget build(BuildContext context) {
    final b = view.bounds;
    return AspectRatio(
      aspectRatio: b.width / b.height,
      child: LayoutBuilder(
        builder: (context, c) {
          final painter = _AnatomyPainter(view: view, color: color, selected: selected);
          final target = selected == null ? null : view.shapeBoundsOf(selected!);
          Offset? anchor;
          if (callout != null && target != null) {
            final t = painter.toScreen(c.biggest);
            anchor = MatrixUtils.transformPoint(t, target.topCenter);
          }
          return Stack(clipBehavior: Clip.none, children: [
            GestureDetector(
              onTapUp: (d) {
                final g = painter.muscleAt(d.localPosition, c.biggest);
                if (g != null) {
                  HapticFeedback.selectionClick();
                  onTap(g);
                }
              },
              child: CustomPaint(size: c.biggest, painter: painter),
            ),
            if (anchor != null)
              Positioned(
                left: 0,
                right: 0,
                top: math.max(0, anchor.dy - 40),
                child: IgnorePointer(child: Center(child: callout)),
              ),
          ]);
        },
      ),
    );
  }
}

class _AnatomyPainter extends CustomPainter {
  _AnatomyPainter({required this.view, required this.color, required this.selected});

  final BodyView view;
  final Color Function(Muscle) color;
  final Muscle? selected;

  /// Head, hands, feet, joints: darker than any muscle so the muscles read as shapes.
  static const _silhouette = Color(0xFF161A22);

  double _scale(Size size) => math.min(size.width / view.bounds.width, size.height / view.bounds.height);

  Matrix4 toScreen(Size size) {
    final b = view.bounds;
    final s = _scale(size);
    final dx = (size.width - b.width * s) / 2 - b.left * s;
    final dy = (size.height - b.height * s) / 2 - b.top * s;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  Muscle? muscleAt(Offset p, Size size) {
    final local = MatrixUtils.transformPoint(Matrix4.inverted(toScreen(size)), p);
    for (final r in view.shapes.reversed) {
      if (r.path.contains(local)) return r.muscle;
    }
    // Forgiving taps: the nearest muscle within ~14 screen px.
    Muscle? best;
    var bestD = 14 / _scale(size);
    for (final r in view.shapes) {
      final d = (r.path.getBounds().center - local).distance;
      if (d < bestD) {
        bestD = d;
        best = r.muscle;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = _scale(size);
    canvas.save();
    canvas.transform(toScreen(size).storage);
    for (final p in view.silhouette) {
      canvas.drawPath(p.path, Paint()..color = _silhouette);
    }
    // Flat fills; a background-colored stroke cuts a clear dark gap between neighbouring muscles.
    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 / s
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.background;
    for (final m in view.shapes) {
      canvas.drawPath(m.path, Paint()..color = color(m.muscle));
      canvas.drawPath(m.path, gap);
    }
    if (selected != null) {
      for (final m in view.shapes.where((x) => x.muscle == selected)) {
        canvas.drawPath(
          m.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7 / s
            ..color = Colors.white.withValues(alpha: 0.6)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 / s),
        );
        canvas.drawPath(
          m.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4 / s
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnatomyPainter old) => true;
}

/// Callout shown on tap: badge + muscle name (+ the mode's value).
class MuscleCallout extends StatelessWidget {
  const MuscleCallout({super.key, required this.muscle, this.score, this.trailing});
  final Muscle muscle;
  final RankScore? score;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('muscle-callout'),
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceTop,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outlineBright),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          RankBadge(score: score, size: BadgeSize.small, width: 22, animate: false),
          const SizedBox(width: 6),
          Text(muscle.label, style: AppType.bodyS.copyWith(fontWeight: FontWeight.w800, fontSize: 13)),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Text(trailing!, style: AppType.bodyS.copyWith(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ]),
      );
}

/// Small body silhouette (the view that shows [muscle]) with that muscle highlighted in [color],
/// cropped around the torso or legs so the muscle is visible at thumbnail size.
class MuscleThumbnail extends ConsumerWidget {
  const MuscleThumbnail({super.key, required this.muscle, required this.color, this.size = 44});

  final Muscle muscle;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(bodyMapProvider).value;
    return SizedBox(
      width: size,
      height: size,
      child: map == null ? null : CustomPaint(painter: _ThumbPainter(map.viewFor(muscle), muscle, color)),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.view, this.muscle, this.color);
  final BodyView view;
  final Muscle muscle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final target = view.boundsOf(muscle) ?? view.bounds;
    // A square window centred on the muscle, at least a third of the body tall.
    final side = math.max(view.bounds.height / 3, math.max(target.width, target.height) * 1.6);
    final win = Rect.fromCenter(center: target.center, width: side, height: side);
    final s = size.width / side;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-win.left * s, -win.top * s);
    canvas.scale(s);
    for (final p in view.parts) {
      final c = p.muscle == muscle
          ? color
          : switch (p.role) {
              RegionRole.structure => const Color(0xFF232A3A),
              _ => const Color(0xFF3A4255),
            };
      canvas.drawPath(p.path, Paint()..color = c);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) => old.view != view || old.muscle != muscle || old.color != color;
}

/// Generated exercise thumbnail when there's no 3D GIF: our body silhouette (the side where the
/// exercise works most), cropped around its muscles, prime movers lit in the accent color and helpers
/// dimmer. Never a photo.
class ExerciseMuscleThumb extends ConsumerWidget {
  const ExerciseMuscleThumb({super.key, required this.targets, this.size = 56});
  final MuscleTargets targets;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(bodyMapProvider).value;
    return Container(
      width: size,
      height: size,
      color: AppColors.surfaceHigh,
      child: map == null ? null : CustomPaint(painter: _ExerciseThumbPainter(map, targets)),
    );
  }
}

class _ExerciseThumbPainter extends CustomPainter {
  _ExerciseThumbPainter(this.map, this.targets);
  final BodyMap map;
  final MuscleTargets targets;

  @override
  void paint(Canvas canvas, Size size) {
    double weightOn(BodyView v) => targets.weights.entries.where((e) => v.muscles.contains(e.key) && map.viewFor(e.key) == v).fold(0.0, (a, e) => a + e.value);
    final view = weightOn(map.back) > weightOn(map.front) ? map.back : map.front;
    Rect? target;
    for (final e in targets.weights.entries) {
      if (e.value < MuscleTargets.primaryThreshold) continue;
      final b = view.shapeBoundsOf(e.key);
      if (b != null) target = target == null ? b : target.expandToInclude(b);
    }
    target ??= view.bounds;
    final side = math.max(view.bounds.height / 2.6, math.max(target.width, target.height) * 1.35);
    final win = Rect.fromCenter(center: target.center, width: side, height: side);
    final s = size.width / side;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-win.left * s, -win.top * s);
    canvas.scale(s);
    for (final p in view.silhouette) {
      canvas.drawPath(p.path, Paint()..color = const Color(0xFF2E3542));
    }
    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 / s
      ..color = AppColors.surfaceHigh;
    for (final m in view.shapes) {
      final w = targets.weightFor(m.muscle);
      final c = w >= MuscleTargets.primaryThreshold
          ? AppColors.accent
          : (w > 0 ? AppColors.accent.withValues(alpha: 0.45) : const Color(0xFF3A4252));
      canvas.drawPath(m.path, Paint()..color = c);
      canvas.drawPath(m.path, gap);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ExerciseThumbPainter old) => old.targets != targets;
}
