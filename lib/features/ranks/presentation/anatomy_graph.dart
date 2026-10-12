import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/muscle_group.dart';
import '../../../core/theme/app_theme.dart';
import '../data/body_map.dart';
import '../domain/body_regions.dart';
import '../domain/ranks.dart';

final bodyMapProvider = FutureProvider<BodyMap>((ref) => BodyMap.load());

enum BodyGraphMode { ranks, volume }

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

/// Anatomical front/back muscle map. Regions are coloured by tier (ranks mode) or by
/// last-7-days volume vs. the 4-week average (volume mode). Flips front ↔ back with a 3D card turn.
class AnatomyGraph extends ConsumerStatefulWidget {
  const AnatomyGraph({
    super.key,
    required this.back,
    required this.mode,
    required this.scores,
    required this.volume,
    required this.onTap,
    this.selected,
  });

  final bool back;
  final BodyGraphMode mode;
  final Map<MuscleGroup, RankScore?> scores;
  final Map<MuscleGroup, GroupVolume> volume;
  final MuscleGroup? selected;
  final ValueChanged<MuscleGroup> onTap;

  @override
  ConsumerState<AnatomyGraph> createState() => _AnatomyGraphState();
}

class _AnatomyGraphState extends ConsumerState<AnatomyGraph> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.back ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant AnatomyGraph old) {
    super.didUpdateWidget(old);
    if (old.back != widget.back) {
      widget.back ? _flip.forward() : _flip.reverse();
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = ref.watch(bodyMapProvider);
    return map.when(
      loading: () => const AspectRatio(aspectRatio: 0.5, child: SizedBox()),
      error: (e, _) => Text('Body map failed to load: $e'),
      data: (m) => AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_flip.value);
          final angle = t * math.pi;
          final showBack = angle > math.pi / 2;
          final view = showBack ? m.back : m.front;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(showBack ? angle - math.pi : angle),
            child: _ViewCanvas(
              view: view,
              mode: widget.mode,
              scores: widget.scores,
              volume: widget.volume,
              selected: widget.selected,
              onTap: widget.onTap,
            ),
          );
        },
      ),
    );
  }
}

class _ViewCanvas extends StatelessWidget {
  const _ViewCanvas({
    required this.view,
    required this.mode,
    required this.scores,
    required this.volume,
    required this.selected,
    required this.onTap,
  });

  final BodyView view;
  final BodyGraphMode mode;
  final Map<MuscleGroup, RankScore?> scores;
  final Map<MuscleGroup, GroupVolume> volume;
  final MuscleGroup? selected;
  final ValueChanged<MuscleGroup> onTap;

  @override
  Widget build(BuildContext context) {
    final b = view.bounds;
    return AspectRatio(
      aspectRatio: b.width / b.height,
      child: LayoutBuilder(
        builder: (context, c) {
          final painter = _AnatomyPainter(view: view, mode: mode, scores: scores, volume: volume, selected: selected);
          return GestureDetector(
            onTapUp: (d) {
              final g = painter.groupAt(d.localPosition, c.biggest);
              if (g != null) {
                HapticFeedback.selectionClick();
                onTap(g);
              }
            },
            child: CustomPaint(size: c.biggest, painter: painter),
          );
        },
      ),
    );
  }
}

class _AnatomyPainter extends CustomPainter {
  _AnatomyPainter({required this.view, required this.mode, required this.scores, required this.volume, required this.selected});

  final BodyView view;
  final BodyGraphMode mode;
  final Map<MuscleGroup, RankScore?> scores;
  final Map<MuscleGroup, GroupVolume> volume;
  final MuscleGroup? selected;

  static const _structure = Color(0xFF232A3A);
  static const _neutral = Color(0xFF30384A);

  Matrix4 _transform(Size size) {
    final b = view.bounds;
    final s = math.min(size.width / b.width, size.height / b.height);
    final dx = (size.width - b.width * s) / 2 - b.left * s;
    final dy = (size.height - b.height * s) / 2 - b.top * s;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  MuscleGroup? groupAt(Offset p, Size size) {
    final inv = Matrix4.inverted(_transform(size));
    final local = MatrixUtils.transformPoint(inv, p);
    for (final r in view.regions.reversed) {
      if (r.group != null && r.path.contains(local)) return r.group;
    }
    // Forgiving taps: nearest muscle region within a small radius.
    MuscleGroup? best;
    var bestD = 28.0;
    for (final r in view.regions) {
      if (r.group == null) continue;
      final d = (r.path.getBounds().center - local).distance;
      if (d < bestD) {
        bestD = d;
        best = r.group;
      }
    }
    return best;
  }

  Color _colorFor(MuscleGroup g) {
    if (mode == BodyGraphMode.volume) return volumeColor(volumeLevel(volume[g]));
    final s = scores[g];
    return s == null ? AppColors.unranked : tierColors[s.tier.index];
  }

  bool _glows(MuscleGroup g) {
    if (mode == BodyGraphMode.volume) return false;
    final s = scores[g];
    return s != null && s.tier.index >= Tier.platinum.index;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(_transform(size).storage);

    // Glow layer first, so it sits behind every region.
    for (final r in view.regions) {
      final g = r.group;
      if (g == null || !_glows(g)) continue;
      final color = _colorFor(g);
      final tierBoost = (scores[g]!.tier.index - Tier.platinum.index) * 2.0;
      canvas.drawPath(
        r.path,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + tierBoost),
      );
    }

    for (final r in view.regions) {
      final bounds = r.path.getBounds();
      switch (r.role) {
        case RegionRole.structure:
          canvas.drawPath(r.path, Paint()..color = _structure);
        case RegionRole.neutral:
          canvas.drawPath(r.path, Paint()..color = _neutral);
        case RegionRole.muscle:
          final g = r.group!;
          final base = _colorFor(g);
          final ranked = mode == BodyGraphMode.volume || scores[g] != null;
          final hsl = HSLColor.fromColor(base);
          final light = hsl.withLightness((hsl.lightness + 0.14).clamp(0.0, 1.0)).toColor();
          final dark = hsl.withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0)).toColor();
          final alpha = ranked ? 1.0 : 0.55;
          canvas.drawPath(
            r.path,
            Paint()
              ..shader = RadialGradient(
                center: const Alignment(-0.2, -0.3),
                radius: 0.9,
                colors: [light.withValues(alpha: alpha), base.withValues(alpha: alpha), dark.withValues(alpha: alpha)],
                stops: const [0, 0.55, 1],
              ).createShader(bounds),
          );
          if (g == selected) {
            canvas.drawPath(r.path, Paint()..color = Colors.white.withValues(alpha: 0.25));
          }
      }
      canvas.drawPath(
        r.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r.group != null && r.group == selected ? 5 : 1.4
          ..color = r.group != null && r.group == selected ? Colors.white : AppColors.background.withValues(alpha: 0.8),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnatomyPainter old) =>
      old.view != view || old.mode != mode || old.scores != scores || old.volume != volume || old.selected != selected;
}
