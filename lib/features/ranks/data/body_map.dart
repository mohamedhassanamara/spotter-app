import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_parsing/path_parsing.dart';

import '../../../core/domain/muscles.dart';
import '../domain/body_regions.dart';

/// One drawable part of the anatomical map (a slug's path on one side of one view, or a piece of
/// one after splitting).
class BodyPart {
  BodyPart({required this.slug, required this.path, this.muscle}) : role = roleForSlug(slug);

  final String slug;
  final Path path;
  final RegionRole role;
  final Muscle? muscle;
}

/// One flat, tappable shape of a muscle on one side of the body (or across the midline).
class MuscleShape {
  const MuscleShape(this.muscle, this.path);
  final Muscle muscle;
  final Path path;
}

class BodyView {
  BodyView(this.parts) : bounds = _union(parts) {
    shapes = simplifyMuscles(parts, bounds.center.dx);
  }

  final List<BodyPart> parts;
  final Rect bounds;

  /// The 20 muscles as simple shapes: muscles drawn in several fragments (abs, quads, calves…) become
  /// one hull per side; single-piece muscles keep their path. Drawn flat with a dark gap between them.
  late final List<MuscleShape> shapes;

  /// Everything that isn't a muscle (head, hands, feet, knees…), drawn as the silhouette.
  List<BodyPart> get silhouette => [for (final p in parts) if (p.muscle == null) p];

  Rect? shapeBoundsOf(Muscle m) {
    Rect? r;
    for (final s in shapes) {
      if (s.muscle != m) continue;
      final b = s.path.getBounds();
      r = r == null ? b : r.expandToInclude(b);
    }
    return r;
  }

  static Rect _union(List<BodyPart> parts) {
    Rect? r;
    for (final p in parts) {
      final b = p.path.getBounds();
      r = r == null ? b : r.expandToInclude(b);
    }
    return r ?? Rect.zero;
  }

  /// Bounds of every part drawn for [m] in this view, or null.
  Rect? boundsOf(Muscle m) {
    Rect? r;
    for (final p in parts) {
      if (p.muscle != m) continue;
      final b = p.path.getBounds();
      r = r == null ? b : r.expandToInclude(b);
    }
    return r;
  }

  Set<Muscle> get muscles => {for (final p in parts) ?p.muscle};
}

/// Front and back anatomical maps from `assets/body_map.json` (paths from
/// react-native-body-highlighter, MIT), split into the 20 ranking muscles:
/// - chest: top 45 % of each pec → Upper Chest, the rest → Lower Chest;
/// - deltoids: the outer 40 % is Middle Delt; the rest is Front Delt (front view) or Rear Delt (back view);
/// - upper back: the tall lower piece is Lats, the two upper pieces are Upper Back;
/// - gluteal: the small upper piece (glute medius) is Abductors, the rest Glutes.
class BodyMap {
  BodyMap({required this.front, required this.back});

  final BodyView front;
  final BodyView back;

  static BodyMap? _cache;

  static Future<BodyMap> load() async {
    if (_cache != null) return _cache!;
    return _cache = parse(await rootBundle.loadString('assets/body_map.json'));
  }

  BodyView viewFor(Muscle m) => muscleOnBack(m) ? back : front;

  static const double upperChestFraction = 0.45;
  static const double middleDeltFraction = 0.40;

  static BodyMap parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    BodyView view(String key) {
      final isBack = key == 'back';
      final raws = <(String, Path)>[];
      for (final part in (j[key] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final slug = part['slug'] as String;
        for (final side in const ['common', 'left', 'right']) {
          for (final d in (part[side] as List<dynamic>? ?? const []).cast<String>()) {
            raws.add((slug, svgPath(d)));
          }
        }
      }
      var all = raws.first.$2.getBounds();
      for (final r in raws) {
        all = all.expandToInclude(r.$2.getBounds());
      }
      final centerX = all.center.dx;

      final parts = <BodyPart>[];
      for (final (slug, path) in raws) {
        final b = path.getBounds();
        switch (slug) {
          case 'chest':
            final cut = b.top + b.height * upperChestFraction;
            parts.add(BodyPart(slug: slug, path: _clip(path, Rect.fromLTRB(b.left - 1, b.top - 1, b.right + 1, cut)), muscle: Muscle.upperChest));
            parts.add(BodyPart(slug: slug, path: _clip(path, Rect.fromLTRB(b.left - 1, cut, b.right + 1, b.bottom + 1)), muscle: Muscle.lowerChest));
          case 'deltoids':
            final outerIsLeft = b.center.dx < centerX;
            final cut = outerIsLeft ? b.left + b.width * middleDeltFraction : b.right - b.width * middleDeltFraction;
            final outer = outerIsLeft
                ? Rect.fromLTRB(b.left - 1, b.top - 1, cut, b.bottom + 1)
                : Rect.fromLTRB(cut, b.top - 1, b.right + 1, b.bottom + 1);
            final inner = outerIsLeft
                ? Rect.fromLTRB(cut, b.top - 1, b.right + 1, b.bottom + 1)
                : Rect.fromLTRB(b.left - 1, b.top - 1, cut, b.bottom + 1);
            parts.add(BodyPart(slug: slug, path: _clip(path, outer), muscle: Muscle.middleDelt));
            parts.add(BodyPart(slug: slug, path: _clip(path, inner), muscle: isBack ? Muscle.rearDelt : Muscle.frontDelt));
          case 'upper-back':
            parts.add(BodyPart(slug: slug, path: path, muscle: b.height > 100 ? Muscle.lats : Muscle.upperBack));
          case 'gluteal':
            parts.add(BodyPart(slug: slug, path: path, muscle: b.height < 70 ? Muscle.abductors : Muscle.glutes));
          default:
            parts.add(BodyPart(slug: slug, path: path, muscle: bodySlugToMuscle[slug]));
        }
      }
      return BodyView(parts);
    }

    return BodyMap(front: view('front'), back: view('back'));
  }

  static Path _clip(Path p, Rect r) => Path.combine(PathOperation.intersect, p, Path()..addRect(r));
}

Path svgPath(String d) {
  final proxy = _PathProxy();
  writeSvgPathDataToPath(d, proxy);
  return proxy.path;
}

class _PathProxy extends PathProxy {
  final Path path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}

/// Groups each muscle's parts by side (left / right / across the midline) and merges every group of
/// two or more fragments into the convex hull of their outlines.
List<MuscleShape> simplifyMuscles(List<BodyPart> parts, double centerX) {
  final groups = <(Muscle, int), List<Path>>{};
  for (final p in parts) {
    final m = p.muscle;
    if (m == null) continue;
    final b = p.path.getBounds();
    final side = b.left < centerX && b.right > centerX ? 0 : (b.center.dx < centerX ? -1 : 1);
    (groups[(m, side)] ??= []).add(p.path);
  }
  // A muscle that has a midline piece (abs, lower back) merges its side pieces into it.
  for (final key in groups.keys.toList()) {
    if (key.$2 == 0) continue;
    final mid = groups[(key.$1, 0)];
    if (mid != null) mid.addAll(groups.remove(key)!);
  }
  return [
    for (final e in groups.entries) MuscleShape(e.key.$1, e.value.length == 1 ? e.value.single : convexHull(e.value)),
  ];
}

/// Convex hull of the outlines of [paths] (sampled every 2 units), as a closed path.
Path convexHull(List<Path> paths) {
  final pts = <Offset>[];
  for (final p in paths) {
    for (final m in p.computeMetrics()) {
      for (var d = 0.0; d <= m.length; d += 2) {
        final t = m.getTangentForOffset(d);
        if (t != null) pts.add(t.position);
      }
    }
  }
  if (pts.length < 3) return Path()..addPath(paths.first, Offset.zero);
  pts.sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final lower = <Offset>[], upper = <Offset>[];
  for (final p in pts) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  for (final p in pts.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  final hull = [...lower..removeLast(), ...upper..removeLast()];
  return Path()..addPolygon(hull, true);
}
