import 'dart:math' as math;

import '../../../core/domain/muscle_group.dart';
import '../../library/domain/muscle_mapping.dart';

/// One ExerciseDB V1 entry (metadata only; the GIF is downloaded on demand).
class EdbExercise {
  const EdbExercise({
    required this.id,
    required this.name,
    required this.gifUrl,
    required this.equipments,
    required this.targets,
    required this.bodyParts,
  });

  final String id;
  final String name;
  final String gifUrl;
  final List<String> equipments;
  final List<String> targets;
  final List<String> bodyParts;

  factory EdbExercise.fromJson(Map<String, dynamic> j) => EdbExercise(
        id: j['exerciseId'] as String,
        name: j['name'] as String,
        gifUrl: j['gifUrl'] as String,
        equipments: (j['equipments'] as List<dynamic>).cast<String>(),
        targets: (j['targetMuscles'] as List<dynamic>).cast<String>(),
        bodyParts: (j['bodyParts'] as List<dynamic>? ?? const []).cast<String>(),
      );
}

/// What we know about a library exercise when matching.
class LibraryExerciseKey {
  const LibraryExerciseKey({
    required this.id,
    required this.name,
    required this.equipment,
    required this.primaryMuscles,
    this.secondaryMuscles = const [],
  });
  final String id;
  final String name;
  final String? equipment;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
}

class MediaCandidate {
  const MediaCandidate(this.edb, this.score, this.nameScore, this.equipmentScore, this.muscleScore);
  final EdbExercise edb;
  final double score;
  final double nameScore;
  final double equipmentScore;
  final double muscleScore;
}

enum MatchConfidence { high, low, none }

class MediaMatch {
  const MediaMatch({required this.exerciseId, required this.candidates});
  final String exerciseId;

  /// Best first, at most 3.
  final List<MediaCandidate> candidates;

  MediaCandidate? get best => candidates.isEmpty ? null : candidates.first;

  MatchConfidence get confidence => MediaMatcher.confidenceFor(best?.score ?? 0);
}

/// Fuzzy matcher: normalised name similarity (IDF-weighted tokens + character trigrams), equipment
/// compatibility and target-muscle agreement.
class MediaMatcher {
  MediaMatcher(this.edb) {
    for (final e in edb) {
      final tokens = normalizeTokens(e.name).toSet();
      _tokens[e.id] = tokens;
      _trigrams[e.id] = _grams(tokens.join(' '));
      for (final t in tokens) {
        (_index[t] ??= []).add(e);
        _df[t] = (_df[t] ?? 0) + 1;
      }
    }
  }

  final List<EdbExercise> edb;
  final Map<String, Set<String>> _tokens = {};
  final Map<String, Set<String>> _trigrams = {};
  final Map<String, List<EdbExercise>> _index = {};
  final Map<String, int> _df = {};

  static const double wName = 0.6, wEquipment = 0.25, wMuscle = 0.15;
  static const double highThreshold = 0.72;
  static const double lowThreshold = 0.5;

  static MatchConfidence confidenceFor(double score) =>
      score >= highThreshold ? MatchConfidence.high : (score >= lowThreshold ? MatchConfidence.low : MatchConfidence.none);

  // ---- normalisation ----

  static const _phrases = {
    'pull-up': 'pull up',
    'pullup': 'pull up',
    'pullups': 'pull up',
    'chin-up': 'chin up',
    'chinup': 'chin up',
    'push-up': 'push up',
    'pushup': 'push up',
    'pushups': 'push up',
    'sit-up': 'sit up',
    'situp': 'sit up',
    'e-z': 'ez',
    'dumbell': 'dumbbell',
    'skullcrusher': 'skull crusher',
    'pushdown': 'pushdown',
    'hamstring curl': 'leg curl',
    'military press': 'shoulder press',
    'overhead press': 'shoulder press',
    'hip thrust': 'hip thrust',
    'romanian deadlift': 'romanian deadlift',
    'stiff-legged': 'stiff leg',
    'stiff legged': 'stiff leg',
  };

  // Longest first, so "pullups" isn't half-replaced by "pullup".
  static final _phrasesLongestFirst = _phrases.entries.toList()..sort((a, b) => b.key.length.compareTo(a.key.length));

  static const _singular = {
    'ups': 'up',
    'flyes': 'fly',
    'flys': 'fly',
    'flies': 'fly',
    'raises': 'raise',
    'curls': 'curl',
    'extensions': 'extension',
    'rows': 'row',
    'presses': 'press',
    'squats': 'squat',
    'lunges': 'lunge',
    'deadlifts': 'deadlift',
    'crunches': 'crunch',
    'dips': 'dip',
    'shrugs': 'shrug',
    'kickbacks': 'kickback',
    'pulldowns': 'pulldown',
    'pushdowns': 'pushdown',
    'calves': 'calf',
    'dumbbells': 'dumbbell',
    'kettlebells': 'kettlebell',
  };

  static const _stop = {'the', 'a', 'an', 'with', 'on', 'of', 'to', 'and', 'version', 'medium', 'grip', 'v', 'exercise'};

  static List<String> normalizeTokens(String name) {
    var s = name.toLowerCase();
    for (final e in _phrasesLongestFirst) {
      s = s.replaceAll(e.key, e.value);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final out = <String>[];
    for (var t in s.split(RegExp(r'\s+'))) {
      if (t.isEmpty || _stop.contains(t)) continue;
      t = _singular[t] ?? t;
      if (t.length > 4 && t.endsWith('s') && !t.endsWith('ss')) t = t.substring(0, t.length - 1);
      out.add(t);
    }
    return out;
  }

  static Set<String> _grams(String s) {
    final p = ' $s ';
    return {for (var i = 0; i + 3 <= p.length; i++) p.substring(i, i + 3)};
  }

  double _idf(String t) => math.log((edb.length + 1) / ((_df[t] ?? 0) + 1)) + 1;

  double nameSimilarity(Set<String> a, EdbExercise e) {
    final b = _tokens[e.id]!;
    var common = 0.0, wa = 0.0, wb = 0.0;
    for (final t in a) {
      wa += _idf(t);
      if (b.contains(t)) common += _idf(t);
    }
    for (final t in b) {
      wb += _idf(t);
    }
    final tokenDice = (wa + wb) == 0 ? 0.0 : 2 * common / (wa + wb);
    final ga = _grams(a.join(' ')), gb = _trigrams[e.id]!;
    final triDice = (ga.isEmpty || gb.isEmpty) ? 0.0 : 2 * ga.intersection(gb).length / (ga.length + gb.length);
    return 0.7 * tokenDice + 0.3 * triDice;
  }

  // ---- equipment ----

  static const Map<String, Set<String>> _equipment = {
    'barbell': {'barbell', 'olympic barbell', 'trap bar'},
    'dumbbell': {'dumbbell'},
    'cable': {'cable', 'rope'},
    'machine': {'leverage machine', 'smith machine', 'sled machine'},
    'kettlebells': {'kettlebell'},
    'body only': {'bodyweight', 'weighted', 'assisted'},
    'bands': {'resistance band', 'band'},
    'e-z curl bar': {'ez bar'},
    'medicine ball': {'medicine ball'},
    'exercise ball': {'stability ball'},
    'foam roll': {'roller'},
  };

  /// 1 = compatible, 0.6 = compatible but needs extra kit (e.g. "… on exercise ball"), 0 = different.
  static double equipmentScore(String? ours, List<String> theirs) {
    final ok = ours == null ? null : _equipment[ours.toLowerCase()];
    if (ok == null) return 0.5; // "other" / unknown
    final hits = theirs.where((e) => ok.contains(e.toLowerCase())).length;
    if (hits == 0) return 0;
    return hits == theirs.length ? 1 : 0.6;
  }

  // ---- muscles ----

  static const Map<String, MuscleGroup?> _edbMuscle = {
    'abdominals': MuscleGroup.abs,
    'pectorals': MuscleGroup.chest,
    'glutes': MuscleGroup.glutes,
    'biceps': MuscleGroup.biceps,
    'triceps': MuscleGroup.triceps,
    'deltoids': MuscleGroup.shoulders,
    'upper back': MuscleGroup.back,
    'latissimus dorsi': MuscleGroup.back,
    'calves': MuscleGroup.calves,
    'quadriceps': MuscleGroup.quads,
    'forearms': MuscleGroup.forearms,
    'hamstrings': MuscleGroup.hamstrings,
    'trapezius': MuscleGroup.traps,
    'levator scapulae': MuscleGroup.traps,
    'abductors': MuscleGroup.glutes,
  };

  /// 1 when their target is one of our primary muscles, 0.7 when it's one of our secondary ones.
  static double muscleScore(List<String> ourPrimary, List<String> theirTargets, [List<String> ourSecondary = const []]) {
    final ours = {for (final m in ourPrimary) ?groupForDatasetMuscle(m)};
    final oursSecondary = {for (final m in ourSecondary) ?groupForDatasetMuscle(m)};
    final theirs = {for (final m in theirTargets) ?_edbMuscle[m.toLowerCase()]};
    // Unranked muscles on both sides (lower back ↔ erector spinae, adductors ↔ adductors).
    if (ourPrimary.contains('lower back') && theirTargets.contains('erector spinae')) return 1;
    if (ourPrimary.contains('adductors') && theirTargets.contains('adductors')) return 1;
    if (ours.isEmpty || theirs.isEmpty) return 0.5;
    if (ours.intersection(theirs).isNotEmpty) return 1;
    return oursSecondary.intersection(theirs).isNotEmpty ? 0.7 : 0;
  }

  // ---- matching ----

  MediaMatch match(LibraryExerciseKey ex) {
    final tokens = normalizeTokens(ex.name).toSet();
    final pool = <String, EdbExercise>{};
    for (final t in tokens) {
      for (final e in _index[t] ?? const <EdbExercise>[]) {
        pool[e.id] = e;
      }
    }
    final scored = <MediaCandidate>[];
    for (final e in pool.values) {
      final n = nameSimilarity(tokens, e);
      if (n < 0.2) continue;
      final eq = equipmentScore(ex.equipment, e.equipments);
      final mu = muscleScore(ex.primaryMuscles, e.targets, ex.secondaryMuscles);
      scored.add(MediaCandidate(e, wName * n + wEquipment * eq + wMuscle * mu, n, eq, mu));
    }
    // Ties go to the shorter name (fewer extra qualifiers like "(on knees)").
    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.edb.name.length.compareTo(b.edb.name.length);
    });
    return MediaMatch(exerciseId: ex.id, candidates: scored.take(3).toList());
  }
}
