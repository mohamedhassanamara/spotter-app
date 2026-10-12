import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_parsing/path_parsing.dart';

import '../../../core/domain/muscle_group.dart';
import '../domain/body_regions.dart';

/// One drawable region of the anatomical map (a slug on one side of one view).
class BodyRegion {
  BodyRegion({required this.slug, required this.path}) : role = roleForSlug(slug), group = bodySlugToGroup[slug];

  final String slug;
  final Path path;
  final RegionRole role;
  final MuscleGroup? group;
}

class BodyView {
  BodyView(this.regions) : bounds = _union(regions);

  final List<BodyRegion> regions;
  final Rect bounds;

  static Rect _union(List<BodyRegion> regions) {
    Rect? r;
    for (final reg in regions) {
      final b = reg.path.getBounds();
      r = r == null ? b : r.expandToInclude(b);
    }
    return r ?? Rect.zero;
  }
}

/// Front and back anatomical muscle maps from `assets/body_map.json`
/// (paths from react-native-body-highlighter, MIT).
class BodyMap {
  BodyMap({required this.front, required this.back});

  final BodyView front;
  final BodyView back;

  static BodyMap? _cache;

  static Future<BodyMap> load() async {
    if (_cache != null) return _cache!;
    return _cache = parse(await rootBundle.loadString('assets/body_map.json'));
  }

  static BodyMap parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    BodyView view(String key) {
      final regions = <BodyRegion>[];
      for (final part in (j[key] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final slug = part['slug'] as String;
        for (final side in const ['common', 'left', 'right']) {
          for (final d in (part[side] as List<dynamic>? ?? const []).cast<String>()) {
            regions.add(BodyRegion(slug: slug, path: svgPath(d)));
          }
        }
      }
      return BodyView(regions);
    }

    return BodyMap(front: view('front'), back: view('back'));
  }
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
