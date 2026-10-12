import '../../tutorials/domain/media_matcher.dart';
import 'exercise_info.dart';

class NameMatch {
  const NameMatch(this.exercise, this.score);
  final ExerciseInfo exercise;

  /// 0..1; 1 = exact (case-insensitive) name match.
  final double score;
}

/// Resolves free-text exercise names (program substitutions, Liftoff names) to library exercises:
/// exact case-insensitive name first, then token similarity (Dice on normalised tokens, the same
/// normalisation as the media matcher: plurals, "pull-up" spellings, stop-words).
class ExerciseNameResolver {
  ExerciseNameResolver(Iterable<ExerciseInfo> catalog) : _all = catalog.toList() {
    for (final e in _all) {
      _exact[_key(e.name)] = e;
      _tokens[e.id] = MediaMatcher.normalizeTokens(_expand(e.name)).toSet();
    }
  }

  final List<ExerciseInfo> _all;
  final Map<String, ExerciseInfo> _exact = {};
  final Map<String, Set<String>> _tokens = {};

  static String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Common abbreviations in program and app names.
  static String _expand(String s) => s
      .replaceAll(RegExp(r'\bDB\b'), 'dumbbell')
      .replaceAll(RegExp(r'\bRDL\b'), 'romanian deadlift')
      .replaceAll(RegExp(r'\bFlye\b', caseSensitive: false), 'fly')
      .replaceAll(RegExp(r'\bPressdown\b', caseSensitive: false), 'pushdown');

  static double _dice(Set<String> a, Set<String> b) =>
      (a.isEmpty || b.isEmpty) ? 0 : 2 * a.intersection(b).length / (a.length + b.length);

  /// Best matches, best first.
  List<NameMatch> candidates(String name, {int limit = 3}) {
    final exact = _exact[_key(name)];
    final tokens = MediaMatcher.normalizeTokens(_expand(name)).toSet();
    final scored = <NameMatch>[
      if (exact != null) NameMatch(exact, 1),
      for (final e in _all)
        if (e != exact) NameMatch(e, _dice(tokens, _tokens[e.id]!)),
    ]..sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : a.exercise.name.length.compareTo(b.exercise.name.length);
      });
    return scored.where((m) => m.score > 0).take(limit).toList();
  }

  /// The best match if it's confident enough.
  NameMatch? resolve(String name, {double minScore = 0.6}) {
    final c = candidates(name, limit: 1);
    return c.isNotEmpty && c.first.score >= minScore ? c.first : null;
  }
}
