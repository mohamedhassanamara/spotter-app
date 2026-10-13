import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/muscles.dart';
import '../../../core/theme/app_theme.dart';
import '../data/body_map.dart';
import '../domain/body_regions.dart';
import '../domain/ranks.dart';
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

/// Front and back side by side (no flipping): flat muscle shapes filled by tier (Rank), recovery band
/// (Recovery) or last-7-days volume (Volume), thin dark outlines between regions. The selected muscle
/// gets an outline glow.
class AnatomyGraph extends ConsumerWidget {
  const AnatomyGraph({
    super.key,
    required this.mode,
    required this.scores,
    required this.volume,
    this.recovery,
    required this.onTap,
    this.selected,
  });

  final BodyGraphMode mode;
  final Map<Muscle, RankScore?> scores;
  final Map<Muscle, GroupVolume> volume;
  final RecoveryState? recovery;
  final Muscle? selected;
  final ValueChanged<Muscle> onTap;

  Color colorFor(Muscle m) => switch (mode) {
        BodyGraphMode.ranks => scores[m] == null ? AppColors.unranked : tierColors[scores[m]!.tier.index],
        BodyGraphMode.volume => volumeColor(volumeLevel(volume[m])),
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
        Widget side(BodyView v, String key, String title) => Expanded(
              child: Column(children: [
                _ViewCanvas(key: ValueKey(key), view: v, color: colorFor, selected: selected, onTap: onTap),
                const SizedBox(height: 6),
                Text(title, style: label),
              ]),
            );
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          side(m.front, 'body-front', 'FRONT'),
          const SizedBox(width: 12),
          side(m.back, 'body-back', 'BACK'),
        ]);
      },
    );
  }
}

class _ViewCanvas extends StatelessWidget {
  const _ViewCanvas({super.key, required this.view, required this.color, required this.selected, required this.onTap});

  final BodyView view;
  final Color Function(Muscle) color;
  final Muscle? selected;
  final ValueChanged<Muscle> onTap;

  @override
  Widget build(BuildContext context) {
    final b = view.bounds;
    return AspectRatio(
      aspectRatio: b.width / b.height,
      child: LayoutBuilder(
        builder: (context, c) {
          final painter = _AnatomyPainter(view: view, color: color, selected: selected);
          return GestureDetector(
            onTapUp: (d) {
              final g = painter.muscleAt(d.localPosition, c.biggest);
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
  _AnatomyPainter({required this.view, required this.color, required this.selected});

  final BodyView view;
  final Color Function(Muscle) color;
  final Muscle? selected;

  static const _structure = Color(0xFF1C2230);
  static const _neutral = Color(0xFF2A3142);

  double _scale(Size size) => math.min(size.width / view.bounds.width, size.height / view.bounds.height);

  Matrix4 _transform(Size size) {
    final b = view.bounds;
    final s = _scale(size);
    final dx = (size.width - b.width * s) / 2 - b.left * s;
    final dy = (size.height - b.height * s) / 2 - b.top * s;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  Muscle? muscleAt(Offset p, Size size) {
    final inv = Matrix4.inverted(_transform(size));
    final local = MatrixUtils.transformPoint(inv, p);
    for (final r in view.parts.reversed) {
      if (r.muscle != null && r.path.contains(local)) return r.muscle;
    }
    // Forgiving taps: the nearest muscle within ~14 screen px.
    final radius = 14 / _scale(size);
    Muscle? best;
    var bestD = radius;
    for (final r in view.parts) {
      if (r.muscle == null) continue;
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
    canvas.transform(_transform(size).storage);
    // Flat fills with a thin dark outline (constant on screen whatever the size).
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / s
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.background;
    for (final r in view.parts) {
      final g = r.muscle;
      final fill = switch (r.role) {
        RegionRole.structure => _structure,
        RegionRole.neutral => _neutral,
        RegionRole.muscle => g == null ? _neutral : color(g),
      };
      canvas.drawPath(r.path, Paint()..color = fill);
      // A subtle top highlight keeps the flat shapes from looking like stickers.
      if (g != null) {
        final bounds = r.path.getBounds();
        canvas.drawPath(
          r.path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0)],
              stops: const [0, 0.6],
            ).createShader(bounds),
        );
      }
      canvas.drawPath(r.path, outline);
    }
    // Selected muscle: outline glow on top.
    if (selected != null) {
      for (final r in view.parts.where((p) => p.muscle == selected)) {
        canvas.drawPath(
          r.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6 / s
            ..color = Colors.white.withValues(alpha: 0.55)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 / s),
        );
        canvas.drawPath(
          r.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 / s
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
