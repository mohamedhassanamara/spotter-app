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

/// Original rank emblem (vector, drawn in code, in a faceted-crystal style; nothing here is traced from anyone's
/// artwork). Escalates with the tier: Iron and Bronze are plain flat gems; Silver and Gold are fully faceted with side
/// shards and blades; Platinum glows; Diamond floats shards around the crystal; Champion and Immortal add wings and a
/// crown; Radiant glows, throws rays and shimmers. Each tier is painted with its own two-colour gradient. The division
/// (1–3) is shown as that many lit marks under the emblem; Radiant has none.
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
          painter: EmblemPainter(tier: s?.tier, division: s == null || s.isApex ? 0 : s.divisionIndex + 1, phase: phase),
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

  /// 1–3 lit division marks; 0 = none (Radiant, unranked).
  final int division;

  /// 0..1 loop for Radiant's glow, rays and shimmer.
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
      if (division > 0) _marks(canvas, t, division);
    }
    canvas.restore();
  }

  // ---- palette ----

  static Color _light(Tier t) => tierGradients[t.index].$1;
  static Color _deep(Tier t) => tierGradients[t.index].$2;

  /// The tier's gradient at [f] (0 = lighter, 1 = deeper).
  static Color _at(Tier t, double f) => Color.lerp(_light(t), _deep(t), f.clamp(0.0, 1.0))!;

  static Color _shade(Color c, double amount) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  // ---- geometry (the crystal) ----

  static const _top = Offset(60, 14), _ur = Offset(90, 36), _lr = Offset(80, 86), _bot = Offset(60, 106), _ll = Offset(40, 86), _ul = Offset(30, 36);
  static const _t1 = Offset(60, 30), _t2 = Offset(77, 47), _t3 = Offset(60, 84), _t4 = Offset(43, 47);

  /// Facets with where they sit on the gradient (0 lighter … 1 deeper).
  static const List<(List<Offset>, double)> _facets = [
    ([_ul, _top, _t1, _t4], 0.0),
    ([_top, _ur, _t2, _t1], 0.22),
    ([_t4, _t1, _t2, _t3], 0.1), // table
    ([_ur, _lr, _t3, _t2], 0.72),
    ([_ul, _t4, _t3, _ll], 0.45),
    ([_ll, _bot, _lr, _t3], 1.0),
  ];

  static Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  static Path _outline() => _poly([_top, _ur, _lr, _bot, _ll, _ul]);

  static Path _mirror(Path p) => p.transform((Matrix4.identity()
        ..translateByDouble(120, 0, 0, 1)
        ..scaleByDouble(-1, 1, 1, 1))
      .storage);

  // ---- emblem ----

  void _emblem(Canvas canvas, Tier t) {
    final i = t.index;
    final ornate = i >= Tier.champion.index;
    canvas.save();
    // Small tiers are drawn a little smaller; crowned tiers make room for the crown.
    final s = switch (t) {
      Tier.iron => 0.82,
      Tier.bronze => 0.88,
      Tier.champion || Tier.immortal || Tier.radiant => 0.9,
      _ => 1.0,
    };
    final cy = ornate ? 66.0 : 58.0;
    canvas.translate(60, cy);
    canvas.scale(s);
    canvas.translate(-60, -58);

    if (i >= Tier.platinum.index) _glow(canvas, t);
    if (t == Tier.radiant) _rays(canvas, t);
    if (ornate) _wings(canvas, t);
    if (t == Tier.diamond) _floatingShards(canvas, t);
    if (i == Tier.silver.index) _sideShards(canvas, t, 1);
    if (i == Tier.gold.index) _sideShards(canvas, t, 2);
    if (i == Tier.platinum.index) _sideShards(canvas, t, 3);

    canvas.drawPath(_outline().shift(const Offset(0, 3)), Paint()..color = Colors.black.withValues(alpha: 0.35));
    _crystal(canvas, t);
    if (ornate) _crown(canvas, t);
    if (t == Tier.immortal) _beam(canvas, t);
    if (t == Tier.radiant) _shimmer(canvas, _outline());
    canvas.restore();
  }

  /// The faceted body: Iron is three flat planes, Bronze four, the rest the full set with a lit table.
  void _crystal(Canvas canvas, Tier t) {
    final i = t.index;
    final facets = i == 0
        ? [(_poly([_ul, _top, _bot, _ll]), 0.15), (_poly([_top, _ur, _lr, _bot]), 0.85)]
        : i == 1
            ? [(_poly([_ul, _top, _t1, _t3, _ll]), 0.1), (_poly([_top, _ur, _t2, _t1]), 0.3), (_poly([_ur, _lr, _t3, _t2]), 0.7), (_poly([_ll, _bot, _lr, _t3]), 1.0)]
            : [for (final (pts, f) in _facets) (_poly(pts), f)];
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = i == 0 ? 1.0 : 1.2
      ..strokeJoin = StrokeJoin.round
      ..color = _deep(t).withValues(alpha: 0.85);
    for (final (path, f) in facets) {
      canvas.drawPath(path, Paint()..color = _at(t, f));
      canvas.drawPath(path, stroke);
    }
    if (i >= Tier.silver.index) {
      // A light catching the top-left edge.
      canvas.drawPath(
        Path()..moveTo(_ul.dx, _ul.dy)..lineTo(_top.dx, _top.dy)..lineTo(_ur.dx, _ur.dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.6),
      );
    }
    canvas.drawPath(
      _outline(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i <= 1 ? 2.2 : 3
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_shade(_light(t), 0.05), _shade(_deep(t), -0.12)])
            .createShader(const Rect.fromLTWH(30, 14, 60, 92)),
    );
    if (i >= Tier.platinum.index) {
      // The table lights up from inside.
      canvas.drawPath(
        _poly([_t1, _t2, _t3, _t4]),
        Paint()
          ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0)]).createShader(const Rect.fromLTWH(43, 30, 34, 54)),
      );
    }
  }

  void _glow(Canvas canvas, Tier t) {
    final a = t == Tier.radiant ? 0.35 + 0.2 * math.sin(phase * math.pi * 2) : (t.index >= Tier.champion.index ? 0.3 : 0.2);
    canvas.drawCircle(const Offset(60, 58), 46, Paint()
      ..color = _light(t).withValues(alpha: a)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
  }

  /// Silver 1 / Gold 2 / Platinum 3 pairs of angular shards at the sides.
  void _sideShards(Canvas canvas, Tier t, int pairs) {
    for (var k = 0; k < pairs; k++) {
      final y = 38.0 + k * 15;
      final reach = 16.0 + (pairs - k) * 3;
      final shard = Path()
        ..moveTo(33, y)
        ..lineTo(33 - reach, y - 10)
        ..lineTo(33 - reach + 7, y + 4)
        ..lineTo(34, y + 12)
        ..close();
      for (final p in [shard, _mirror(shard)]) {
        canvas.drawPath(p, Paint()..shader = LinearGradient(colors: [_light(t), _deep(t)]).createShader(p.getBounds()));
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..strokeJoin = StrokeJoin.round
            ..color = _shade(_deep(t), -0.12),
        );
      }
    }
  }

  void _floatingShards(Canvas canvas, Tier t) {
    for (final (c, r) in const [(Offset(22, 30), 7.0), (Offset(14, 62), 5.0), (Offset(20, 90), 6.0)]) {
      final d = Path()..addPolygon([c + Offset(0, -r * 1.5), c + Offset(r, 0), c + Offset(0, r * 1.5), c + Offset(-r, 0)], true);
      for (final p in [d, _mirror(d)]) {
        canvas.drawPath(p, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_light(t), _deep(t)]).createShader(p.getBounds()));
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.55),
        );
      }
    }
  }

  /// Champion 3, Immortal 4, Radiant 5 angular feathers on each side.
  void _wings(Canvas canvas, Tier t) {
    final n = switch (t) {
      Tier.champion => 3,
      Tier.immortal => 4,
      _ => 5,
    };
    for (var k = 0; k < n; k++) {
      final y = 30.0 + k * 11;
      final reach = 20.0 + (n - k) * 5.5;
      final f = Path()
        ..moveTo(35, y)
        ..lineTo(35 - reach, y - 16 - (n - k) * 1.5)
        ..lineTo(35 - reach + 11, y - 2)
        ..lineTo(35 - reach + 6, y + 9)
        ..lineTo(37, y + 9)
        ..close();
      for (final p in [f, _mirror(f)]) {
        canvas.drawPath(p, Paint()..shader = LinearGradient(colors: [_at(t, 0.1 + k * 0.12), _deep(t)]).createShader(p.getBounds()));
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..strokeJoin = StrokeJoin.round
            ..color = _shade(_deep(t), -0.15),
        );
      }
    }
  }

  /// A crown above the crystal: 3 points (Champion), 5 (Immortal, Radiant).
  void _crown(Canvas canvas, Tier t) {
    final points = t == Tier.champion ? 3 : 5;
    const left = 44.0, right = 76.0, base = 20.0;
    final w = right - left;
    final crown = Path()..moveTo(left, base);
    for (var k = 0; k < points; k++) {
      final x = left + w * (k + 0.5) / points;
      final mid = k == points ~/ 2;
      crown
        ..lineTo(left + w * k / points + (k == 0 ? 0 : 0), k == 0 ? base : base - 6)
        ..lineTo(x, base - (mid ? 17 : 12));
    }
    crown
      ..lineTo(right, base - 6)
      ..lineTo(right, base)
      ..close();
    canvas.drawPath(crown, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_light(t), _deep(t)]).createShader(crown.getBounds()));
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = _shade(_deep(t), -0.18),
    );
    canvas.drawCircle(const Offset(60, 12), 2.2, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  /// Immortal: a bright seam down the middle of the crystal.
  void _beam(Canvas canvas, Tier t) {
    final p = Path()..addPolygon([const Offset(60, 18), const Offset(66, 56), const Offset(60, 100), const Offset(54, 56)], true);
    canvas.drawPath(p, Paint()..color = Colors.white.withValues(alpha: 0.22));
    canvas.drawPath(p, Paint()..color = _light(t).withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  /// Radiant: thin rays turning slowly behind the emblem.
  void _rays(Canvas canvas, Tier t) {
    canvas.save();
    canvas.translate(60, 58);
    canvas.rotate(phase * math.pi * 2 * 0.25);
    final ray = Paint()..color = _light(t).withValues(alpha: 0.22);
    for (var k = 0; k < 10; k++) {
      canvas.save();
      canvas.rotate(k * math.pi * 2 / 10);
      canvas.drawPath(Path()..moveTo(-3, -30)..lineTo(0, -62)..lineTo(3, -30)..close(), ray);
      canvas.restore();
    }
    canvas.restore();
  }

  /// A bright diagonal band sweeping across the crystal.
  void _shimmer(Canvas canvas, Path clip) {
    final b = clip.getBounds();
    final x = b.left - 40 + (b.width + 80) * phase;
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawPath(Path()..addPolygon([Offset(x, b.top), Offset(x + 12, b.top), Offset(x - 18, b.bottom), Offset(x - 30, b.bottom)], true), Paint()..color = Colors.white.withValues(alpha: 0.32));
    canvas.restore();
  }

  /// The division: 1–3 diamond marks under the crystal, lit up to the division.
  void _marks(Canvas canvas, Tier t, int lit) {
    const y = 118.0;
    for (var k = 0; k < 3; k++) {
      final x = 60 + (k - 1) * 13.0;
      final d = Path()..addPolygon([Offset(x, y - 6), Offset(x + 5, y), Offset(x, y + 6), Offset(x - 5, y)], true);
      if (k < lit) {
        canvas.drawPath(d, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_light(t), _deep(t)]).createShader(d.getBounds()));
        canvas.drawPath(
          d,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.7),
        );
      } else {
        canvas.drawPath(d, Paint()..color = Colors.black.withValues(alpha: 0.35));
        canvas.drawPath(
          d,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = _deep(t).withValues(alpha: 0.7),
        );
      }
    }
  }

  void _unranked(Canvas canvas) {
    final gem = _outline().shift(const Offset(0, 2));
    canvas.drawPath(gem, Paint()..color = AppColors.unranked.withValues(alpha: 0.25));
    canvas.drawPath(
      gem,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.unranked,
    );
    final tp = TextPainter(
      text: const TextSpan(text: '?', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: AppColors.textSecondary)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(60 - tp.width / 2, 58 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant EmblemPainter old) => old.tier != tier || old.division != division || old.phase != phase;
}
