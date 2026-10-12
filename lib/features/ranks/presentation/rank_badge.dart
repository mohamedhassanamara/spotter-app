import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/ranks.dart';

enum BadgeSize {
  small(30),
  medium(68),
  hero(184);

  const BadgeSize(this.width);
  final double width;
}

/// Original rank emblem (vector, drawn in code). Escalates with the tier:
/// matte shields → metallic with rim → gem with side flares → crystal with wings →
/// crowned, layered, animated glow and shimmer for the apex tiers.
/// Divisional tiers carry their numeral (IV–I) on a banner under the emblem.
class RankBadge extends StatefulWidget {
  const RankBadge({super.key, required this.score, this.size = BadgeSize.medium, this.animate = true, this.width});

  final RankScore? score;
  final BadgeSize size;

  /// Apex shimmer/glow. Disable in long lists.
  final bool animate;

  /// Overrides [size]'s width.
  final double? width;

  static const double aspect = 130 / 120; // height / width

  @override
  State<RankBadge> createState() => _RankBadgeState();
}

class _RankBadgeState extends State<RankBadge> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  bool get _animated => widget.animate && (widget.score?.isApex ?? false);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RankBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_animated && _c == null) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
    } else if (!_animated && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width ?? widget.size.width;
    final s = widget.score;
    final label = s == null ? 'Unranked' : s.label;
    Widget paint(double phase) => CustomPaint(
          size: Size(w, w * RankBadge.aspect),
          painter: EmblemPainter(tier: s?.tier, division: s?.divisionLabel ?? '', phase: phase),
        );
    return Semantics(
      label: '$label rank',
      child: RepaintBoundary(
        child: _c == null ? paint(0) : AnimatedBuilder(animation: _c!, builder: (_, _) => paint(_c!.value)),
      ),
    );
  }
}

/// Paints one emblem in a 120 × 130 design box.
class EmblemPainter extends CustomPainter {
  EmblemPainter({required this.tier, required this.division, this.phase = 0});

  /// Null = unranked.
  final Tier? tier;
  final String division;

  /// 0..1 loop for apex glow and shimmer.
  final double phase;

  static const _w = 120.0, _h = 130.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / _w, size.height / _h);
    canvas.save();
    canvas.translate((size.width - _w * scale) / 2, (size.height - _h * scale) / 2);
    canvas.scale(scale);
    final t = tier;
    if (t == null) {
      _unranked(canvas);
    } else {
      _emblem(canvas, t);
      if (!t.isApex && division.isNotEmpty) _banner(canvas, t, division);
    }
    canvas.restore();
  }

  // ---- palette ----

  static Color _base(Tier t) => tierColors[t.index];
  static Color _shade(Color c, double amount) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  // ---- shapes ----

  /// Heater shield centred on x = 60.
  static Path _shield({double top = 14, double bottom = 104, double half = 34}) {
    const cx = 60.0;
    final h = bottom - top;
    return Path()
      ..moveTo(cx, top)
      ..quadraticBezierTo(cx + half * 0.55, top + h * 0.06, cx + half, top + h * 0.1)
      ..cubicTo(cx + half, top + h * 0.52, cx + half * 0.62, top + h * 0.8, cx, bottom)
      ..cubicTo(cx - half * 0.62, top + h * 0.8, cx - half, top + h * 0.52, cx - half, top + h * 0.1)
      ..quadraticBezierTo(cx - half * 0.55, top + h * 0.06, cx, top)
      ..close();
  }

  static Path _scaled(Path p, double s, Offset about) {
    final m = Matrix4.identity()
      ..translateByDouble(about.dx, about.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-about.dx, -about.dy, 0, 1);
    return p.transform(m.storage);
  }

  static Path _mirror(Path p) => p.transform((Matrix4.identity()
        ..translateByDouble(120, 0, 0, 1)
        ..scaleByDouble(-1, 1, 1, 1))
      .storage);

  // ---- tiers ----

  void _emblem(Canvas canvas, Tier t) {
    final base = _base(t);
    final apex = t.isApex;
    final shield = apex ? _shield(top: 30, bottom: 112, half: 30) : _shield();
    final shieldBounds = shield.getBounds();

    if (apex) _apexBackdrop(canvas, t, base);
    if (t.index >= Tier.diamond.index) _wings(canvas, t, base, apex: apex);
    if (t == Tier.platinum || t == Tier.emerald) _flares(canvas, base);

    // Body.
    final metallic = t.index >= Tier.silver.index;
    final fill = Paint()
      ..shader = metallic
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_shade(base, 0.22), base, _shade(base, -0.18), base, _shade(base, 0.12)],
              stops: const [0, 0.3, 0.55, 0.78, 1],
            ).createShader(shieldBounds)
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_shade(base, 0.04), _shade(base, -0.12)],
            ).createShader(shieldBounds);
    canvas.drawPath(shield.shift(const Offset(0, 3)), Paint()..color = Colors.black.withValues(alpha: 0.35));

    if (t == Tier.diamond || apex) {
      _crystal(canvas, shield, base);
    } else {
      canvas.drawPath(shield, fill);
    }

    // Rim.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = metallic ? 4 : 3
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: metallic ? [_shade(base, 0.32), _shade(base, -0.25)] : [_shade(base, -0.1), _shade(base, -0.28)],
      ).createShader(shieldBounds);
    canvas.drawPath(shield, rim);
    final inner = _scaled(shield, 0.8, shieldBounds.center);
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _shade(base, metallic ? -0.3 : -0.22).withValues(alpha: 0.8),
    );

    // Centre mark.
    final c = Offset(60, shieldBounds.top + shieldBounds.height * 0.46);
    switch (t) {
      case Tier.iron:
        _bars(canvas, c, base, 1);
      case Tier.bronze:
        _bars(canvas, c, base, 2);
      case Tier.silver:
        _chevrons(canvas, c, base, 2);
      case Tier.gold:
        _chevrons(canvas, c, base, 3);
      case Tier.platinum:
      case Tier.emerald:
        _gem(canvas, c, t == Tier.emerald ? const Color(0xFF34E39A) : const Color(0xFFBFFFF4), 15);
      case Tier.diamond:
        _gem(canvas, c, const Color(0xFFDDE8FF), 12);
      case Tier.master:
      case Tier.grandmaster:
      case Tier.challenger:
        _gem(canvas, c, _shade(base, 0.2), 13);
    }

    if (apex) {
      _crown(canvas, t, base, shieldBounds.top);
      _shimmer(canvas, shield);
    }
  }

  void _bars(Canvas canvas, Offset c, Color base, int n) {
    final p = Paint()..color = _shade(base, -0.3);
    for (var i = 0; i < n; i++) {
      final y = c.dy - (n - 1) * 7 + i * 14;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(c.dx, y), width: 30, height: 7), const Radius.circular(2)),
        p,
      );
    }
  }

  void _chevrons(Canvas canvas, Offset c, Color base, int n) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _shade(base, -0.32);
    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = _shade(base, 0.3).withValues(alpha: 0.7);
    for (var i = 0; i < n; i++) {
      final y = c.dy + 8 - i * 11 + (n - 2) * 5;
      final path = Path()
        ..moveTo(c.dx - 15, y + 7)
        ..lineTo(c.dx, y - 4)
        ..lineTo(c.dx + 15, y + 7);
      canvas.drawPath(path, stroke);
      canvas.drawPath(path.shift(const Offset(0, -2)), hi);
    }
  }

  /// Faceted hexagonal gem.
  void _gem(Canvas canvas, Offset c, Color color, double r) {
    final pts = [for (var i = 0; i < 6; i++) c + Offset(math.cos(math.pi / 3 * i - math.pi / 2), math.sin(math.pi / 3 * i - math.pi / 2)) * r];
    final gem = Path()..addPolygon(pts, true);
    canvas.drawPath(
      gem,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Colors.white, color, _shade(color, -0.35)],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final facet = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Colors.white.withValues(alpha: 0.55);
    final innerPts = [for (final p in pts) Offset.lerp(c, p, 0.5)!];
    canvas.drawPath(Path()..addPolygon(innerPts, true), facet);
    for (var i = 0; i < 6; i++) {
      canvas.drawLine(innerPts[i], pts[i], facet);
    }
    canvas.drawPath(
      gem,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _shade(color, -0.45),
    );
  }

  /// Platinum / Emerald: angular blades on both sides.
  void _flares(Canvas canvas, Color base) {
    final left = Path()
      ..moveTo(28, 30)
      ..lineTo(6, 22)
      ..quadraticBezierTo(14, 40, 26, 50)
      ..lineTo(10, 54)
      ..quadraticBezierTo(20, 66, 32, 68)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(colors: [_shade(base, -0.25), _shade(base, 0.15)])
          .createShader(const Rect.fromLTWH(6, 22, 26, 46));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _shade(base, -0.4);
    for (final p in [left, _mirror(left)]) {
      canvas.drawPath(p, paint);
      canvas.drawPath(p, edge);
    }
  }

  /// Diamond and apex: feathered wings, three layered feathers per side.
  void _wings(Canvas canvas, Tier t, Color base, {required bool apex}) {
    final top = apex ? 44.0 : 30.0;
    for (var i = 0; i < 3; i++) {
      final y = top + i * 12;
      final reach = 4.0 + i * 7;
      final feather = Path()
        ..moveTo(34, y)
        ..quadraticBezierTo(14, y - 10 + i * 2, reach, y - 4 + i * 3)
        ..quadraticBezierTo(16, y + 8, 34, y + 14)
        ..close();
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [_shade(base, 0.1 - i * 0.08), _shade(base, 0.32 - i * 0.08)],
        ).createShader(Rect.fromLTWH(reach, y - 10, 34 - reach, 26));
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _shade(base, -0.35);
      for (final p in [feather, _mirror(feather)]) {
        canvas.drawPath(p, paint);
        canvas.drawPath(p, edge);
      }
    }
  }

  /// Crystal body: the shield split into lit and shaded facets.
  void _crystal(Canvas canvas, Path shield, Color base) {
    final b = shield.getBounds();
    final c = Offset(b.center.dx, b.top + b.height * 0.46);
    canvas.drawPath(
      shield,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_shade(base, 0.25), base, _shade(base, -0.2)],
        ).createShader(b),
    );
    canvas.save();
    canvas.clipPath(shield);
    final corners = [
      Offset(b.left, b.top),
      Offset(b.center.dx, b.top),
      Offset(b.right, b.top),
      Offset(b.right, b.top + b.height * 0.5),
      Offset(b.center.dx, b.bottom),
      Offset(b.left, b.top + b.height * 0.5),
    ];
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i], z = corners[(i + 1) % corners.length];
      final tri = Path()..addPolygon([c, a, z], true);
      final light = (i % 2 == 0) ? 0.14 : -0.1;
      canvas.drawPath(tri, Paint()..color = _shade(base, light).withValues(alpha: 0.55));
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.35);
    for (final p in corners) {
      canvas.drawLine(c, p, line);
    }
    canvas.restore();
  }

  /// Apex: pulsing glow and a halo ring behind the emblem.
  void _apexBackdrop(Canvas canvas, Tier t, Color base) {
    final pulse = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
    const centre = Offset(60, 66);
    canvas.drawCircle(
      centre,
      58,
      Paint()
        ..shader = RadialGradient(colors: [base.withValues(alpha: 0.35 + 0.25 * pulse), base.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: centre, radius: 58)),
    );
    if (t == Tier.challenger) {
      final ray = Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFF3B0).withValues(alpha: 0.35 + 0.3 * pulse);
      for (var i = 0; i < 12; i++) {
        final a = i * math.pi / 6 + phase * math.pi / 6;
        canvas.drawLine(centre + Offset(math.cos(a), math.sin(a)) * 46, centre + Offset(math.cos(a), math.sin(a)) * 58, ray);
      }
    }
    canvas.drawCircle(
      centre,
      44,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = t == Tier.master ? 2 : 3
        ..color = _shade(base, 0.25).withValues(alpha: 0.7),
    );
    if (t != Tier.master) {
      canvas.drawCircle(
        centre,
        49,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _shade(base, 0.1).withValues(alpha: 0.5),
      );
    }
  }

  void _crown(Canvas canvas, Tier t, Color base, double shieldTop) {
    final points = t == Tier.master ? 3 : 5;
    const left = 36.0, right = 84.0;
    final bottom = shieldTop + 6;
    final top = bottom - (t == Tier.challenger ? 26 : 22);
    // Evenly spaced peaks (the centre one tallest), valleys halfway between them.
    final crown = Path()..moveTo(left, bottom);
    final gap = (right - left) / (points - 1);
    for (var k = 0; k < points; k++) {
      final x = left + gap * k;
      final centre = k == points ~/ 2;
      if (k > 0) crown.lineTo(x - gap / 2, bottom - 8);
      crown.lineTo(x, centre ? top - 4 : top);
    }
    crown
      ..lineTo(right, bottom)
      ..close();
    final gold = t == Tier.grandmaster ? const Color(0xFFFFD27A) : const Color(0xFFFFE27A);
    final b = crown.getBounds();
    canvas.drawPath(
      crown,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_shade(gold, 0.15), gold, _shade(gold, -0.25)],
        ).createShader(b),
    );
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _shade(gold, -0.45),
    );
    final jewel = Paint()..color = _shade(base, 0.05);
    canvas.drawCircle(Offset(60, bottom - 4), 3, jewel);
    if (points == 5) {
      canvas.drawCircle(Offset(48, bottom - 4), 2.2, jewel);
      canvas.drawCircle(Offset(72, bottom - 4), 2.2, jewel);
    }
  }

  /// A bright diagonal band sweeping across the emblem.
  void _shimmer(Canvas canvas, Path clip) {
    final b = clip.getBounds();
    final x = b.left - 40 + (b.width + 80) * phase;
    canvas.save();
    canvas.clipPath(clip);
    final band = Path()..addPolygon([Offset(x, b.top), Offset(x + 14, b.top), Offset(x - 16, b.bottom), Offset(x - 30, b.bottom)], true);
    canvas.drawPath(band, Paint()..color = Colors.white.withValues(alpha: 0.28));
    canvas.restore();
  }

  void _banner(Canvas canvas, Tier t, String numeral) {
    final base = _base(t);
    const top = 104.0, bottom = 126.0, left = 30.0, right = 90.0;
    final ribbon = Path()
      ..moveTo(left - 8, top + 2)
      ..lineTo(right + 8, top + 2)
      ..lineTo(right + 2, (top + bottom) / 2 + 1)
      ..lineTo(right + 8, bottom)
      ..lineTo(left - 8, bottom)
      ..lineTo(left - 2, (top + bottom) / 2 + 1)
      ..close();
    canvas.drawPath(ribbon.shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawPath(
      ribbon,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_shade(base, -0.18), _shade(base, -0.34)],
        ).createShader(const Rect.fromLTRB(left, top, right, bottom)),
    );
    canvas.drawPath(
      ribbon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _shade(base, 0.2).withValues(alpha: 0.8),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: numeral,
        style: const TextStyle(
          fontFamily: 'Oxanium',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 1.5,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(60 - tp.width / 2, (top + bottom) / 2 - tp.height / 2 + 1));
  }

  void _unranked(Canvas canvas) {
    final shield = _shield();
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.unranked,
    );
    canvas.drawPath(shield, Paint()..color = AppColors.unranked.withValues(alpha: 0.25));
    final tp = TextPainter(
      text: const TextSpan(text: '?', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: AppColors.textSecondary)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(60 - tp.width / 2, 52 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant EmblemPainter old) => old.tier != tier || old.division != division || old.phase != phase;
}
