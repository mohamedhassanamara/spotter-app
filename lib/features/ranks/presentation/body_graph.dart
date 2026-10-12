import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/domain/muscle_group.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/ranks.dart';

/// Original stylised front/back body silhouette with the 12 ranking regions coloured by tier.
///
/// Geometry lives in a 200 × 440 design space; the left half is drawn and mirrored.
class BodyGraph extends StatelessWidget {
  const BodyGraph({
    super.key,
    required this.scores,
    required this.back,
    required this.onTap,
    this.selected,
  });

  final Map<MuscleGroup, RankScore?> scores;
  final bool back;
  final MuscleGroup? selected;
  final ValueChanged<MuscleGroup> onTap;

  static const Size designSize = Size(200, 440);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: designSize.width / designSize.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final regions = BodyGeometry.regions(back: back);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final p = BodyGeometry.toDesign(d.localPosition, size);
              for (final e in regions.entries) {
                if (e.value.contains(p)) {
                  onTap(e.key);
                  return;
                }
              }
            },
            child: CustomPaint(
              size: size,
              painter: _BodyPainter(regions: regions, scores: scores, selected: selected),
            ),
          );
        },
      ),
    );
  }
}

/// Paths for the silhouette and the muscle regions, in design coordinates.
abstract final class BodyGeometry {
  static const double w = 200, h = 440;

  static double _scale(Size size) => (size.width / w) < (size.height / h) ? size.width / w : size.height / h;

  static Offset _origin(Size size) {
    final s = _scale(size);
    return Offset((size.width - w * s) / 2, (size.height - h * s) / 2);
  }

  static Offset toDesign(Offset local, Size size) {
    final s = _scale(size);
    final o = _origin(size);
    return Offset((local.dx - o.dx) / s, (local.dy - o.dy) / s);
  }

  static Matrix4 toCanvas(Size size) {
    final s = _scale(size);
    final o = _origin(size);
    return Matrix4.identity()
      ..translateByDouble(o.dx, o.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  /// Mirrors a left-side path to the right side around x = 100.
  static Path mirror(Path p) => p.transform(Float64List.fromList([
        -1, 0, 0, 0, //
        0, 1, 0, 0, //
        0, 0, 1, 0, //
        w, 0, 0, 1, //
      ]));

  static Path both(Path left) => Path()
    ..addPath(left, Offset.zero)
    ..addPath(mirror(left), Offset.zero);

  static Path silhouette() {
    final left = Path()
      ..moveTo(100, 54)
      ..lineTo(93, 54)
      ..lineTo(93, 62)
      ..cubicTo(84, 66, 70, 66, 60, 72)
      ..cubicTo(48, 78, 43, 92, 44, 110)
      ..quadraticBezierTo(40, 130, 40, 152)
      ..quadraticBezierTo(34, 180, 32, 210)
      ..quadraticBezierTo(25, 222, 30, 234)
      ..quadraticBezierTo(38, 241, 44, 232)
      ..quadraticBezierTo(46, 222, 47, 212)
      ..quadraticBezierTo(56, 186, 58, 158)
      ..quadraticBezierTo(66, 136, 68, 118)
      ..quadraticBezierTo(70, 150, 76, 172)
      ..quadraticBezierTo(72, 190, 72, 206)
      ..quadraticBezierTo(63, 250, 72, 300)
      ..quadraticBezierTo(74, 312, 75, 320)
      ..quadraticBezierTo(69, 352, 80, 402)
      ..quadraticBezierTo(70, 416, 76, 424)
      ..lineTo(94, 424)
      ..quadraticBezierTo(96, 412, 93, 402)
      ..quadraticBezierTo(98, 360, 96, 320)
      ..quadraticBezierTo(100, 280, 99, 226)
      ..lineTo(100, 224)
      ..close();
    final body = Path.combine(PathOperation.union, left, mirror(left));
    return Path.combine(PathOperation.union, body, Path()..addOval(Rect.fromCircle(center: const Offset(100, 31), radius: 21)));
  }

  static Path _delt() => Path()
    ..moveTo(68, 71)
    ..cubicTo(56, 70, 46, 80, 46, 96)
    ..quadraticBezierTo(46, 104, 48, 110)
    ..quadraticBezierTo(58, 100, 66, 100)
    ..quadraticBezierTo(73, 86, 70, 74)
    ..close();

  static Path _upperArm() => Path()
    ..moveTo(49, 113)
    ..quadraticBezierTo(58, 104, 66, 105)
    ..quadraticBezierTo(66, 129, 58, 152)
    ..quadraticBezierTo(50, 156, 43, 150)
    ..quadraticBezierTo(44, 128, 49, 113)
    ..close();

  static Path _forearm() => Path()
    ..moveTo(42, 157)
    ..quadraticBezierTo(50, 160, 57, 158)
    ..quadraticBezierTo(54, 188, 46, 211)
    ..lineTo(35, 209)
    ..quadraticBezierTo(36, 180, 42, 157)
    ..close();

  static Map<MuscleGroup, Path> regions({required bool back}) {
    if (!back) {
      return {
        MuscleGroup.traps: both(Path()
          ..moveTo(93, 61)
          ..quadraticBezierTo(81, 65, 69, 71)
          ..quadraticBezierTo(82, 73, 93, 70)
          ..close()),
        MuscleGroup.shoulders: both(_delt()),
        MuscleGroup.chest: both(Path()
          ..moveTo(98, 76)
          ..lineTo(98, 116)
          ..cubicTo(90, 121, 76, 118, 70, 108)
          ..quadraticBezierTo(68, 95, 71, 80)
          ..quadraticBezierTo(84, 73, 98, 76)
          ..close()),
        MuscleGroup.biceps: both(_upperArm()),
        MuscleGroup.forearms: both(_forearm()),
        MuscleGroup.abs: both(Path()
          ..moveTo(98, 122)
          ..lineTo(98, 200)
          ..quadraticBezierTo(90, 200, 84, 192)
          ..quadraticBezierTo(79, 160, 80, 125)
          ..quadraticBezierTo(90, 120, 98, 122)
          ..close()),
        MuscleGroup.quads: both(Path()
          ..moveTo(78, 208)
          ..quadraticBezierTo(90, 214, 98, 228)
          ..quadraticBezierTo(98, 270, 94, 302)
          ..quadraticBezierTo(84, 308, 78, 304)
          ..quadraticBezierTo(67, 258, 78, 208)
          ..close()),
        MuscleGroup.calves: both(Path()
          ..moveTo(78, 327)
          ..quadraticBezierTo(86, 322, 94, 327)
          ..quadraticBezierTo(95, 360, 90, 396)
          ..lineTo(82, 396)
          ..quadraticBezierTo(73, 356, 78, 327)
          ..close()),
      };
    }
    return {
      MuscleGroup.traps: both(Path()
        ..moveTo(100, 56)
        ..lineTo(100, 122)
        ..quadraticBezierTo(94, 104, 86, 86)
        ..quadraticBezierTo(78, 78, 69, 72)
        ..quadraticBezierTo(83, 63, 93, 59)
        ..close()),
      MuscleGroup.shoulders: both(_delt()),
      MuscleGroup.back: both(Path()
        ..moveTo(98, 127)
        ..quadraticBezierTo(92, 107, 84, 91)
        ..quadraticBezierTo(76, 85, 71, 87)
        ..quadraticBezierTo(66, 104, 70, 124)
        ..quadraticBezierTo(76, 152, 86, 174)
        ..quadraticBezierTo(94, 178, 98, 176)
        ..close()),
      MuscleGroup.triceps: both(_upperArm()),
      MuscleGroup.forearms: both(_forearm()),
      MuscleGroup.glutes: both(Path()
        ..moveTo(98, 201)
        ..lineTo(98, 246)
        ..quadraticBezierTo(84, 253, 74, 240)
        ..quadraticBezierTo(70, 220, 76, 203)
        ..quadraticBezierTo(88, 196, 98, 201)
        ..close()),
      MuscleGroup.hamstrings: both(Path()
        ..moveTo(76, 253)
        ..quadraticBezierTo(86, 257, 97, 253)
        ..quadraticBezierTo(98, 280, 94, 304)
        ..quadraticBezierTo(84, 309, 78, 305)
        ..quadraticBezierTo(69, 280, 76, 253)
        ..close()),
      MuscleGroup.calves: both(Path()
        ..moveTo(77, 325)
        ..quadraticBezierTo(86, 318, 95, 325)
        ..cubicTo(98, 341, 96, 361, 91, 394)
        ..lineTo(83, 394)
        ..cubicTo(72, 361, 72, 341, 77, 325)
        ..close()),
    };
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({required this.regions, required this.scores, required this.selected});

  final Map<MuscleGroup, Path> regions;
  final Map<MuscleGroup, RankScore?> scores;
  final MuscleGroup? selected;

  static final Path _silhouette = BodyGeometry.silhouette();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(BodyGeometry.toCanvas(size).storage);

    canvas.drawPath(_silhouette, Paint()..color = AppColors.surfaceHigh);
    canvas.drawPath(
      _silhouette,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.outline,
    );

    for (final e in regions.entries) {
      final score = scores[e.key];
      final base = score == null ? AppColors.unranked : tierColor(score.tier);
      final rect = e.value.getBounds();
      canvas.drawPath(
        e.value,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [base.withValues(alpha: 0.95), base.withValues(alpha: 0.7)],
          ).createShader(rect),
      );
      canvas.drawPath(
        e.value,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = AppColors.background.withValues(alpha: 0.85),
      );
    }

    // Ab segments for texture.
    final abs = regions[MuscleGroup.abs];
    if (abs != null) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.background.withValues(alpha: 0.6);
      canvas.save();
      canvas.clipPath(abs);
      for (final y in [146.0, 170.0]) {
        canvas.drawLine(Offset(78, y), Offset(122, y), line);
      }
      canvas.restore();
    }

    final sel = selected == null ? null : regions[selected];
    if (sel != null) {
      canvas.drawPath(
        sel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) =>
      old.regions != regions || old.selected != selected || old.scores != scores;
}
