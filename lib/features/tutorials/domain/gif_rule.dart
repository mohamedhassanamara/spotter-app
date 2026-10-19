import 'media_matcher.dart';

/// Words that change the movement itself (the same name with one of them added or removed is another exercise). Grip width, body
/// position and the like are not in here: they vary the exercise without changing which one it is.
const _modifiers = {
  'incline', 'decline', 'reverse', 'front', 'sumo', 'romanian', 'stiff', 'hammer', 'preacher', 'concentration', 'unilateral', 'bulgarian',
  'goblet', 'hack', 'pendulum', 'walking', 'jump', 'side',
};

/// Other names for the same modifier, and words that imply one (a split squat or a lunge is always one leg at a time).
const _synonyms = {
  'straight': 'stiff',
  'rear': 'reverse',
  'one': 'unilateral',
  'single': 'unilateral',
  'alternate': 'unilateral',
  'alternating': 'unilateral',
  'jumping': 'jump',
  'split': 'unilateral',
  'lunge': 'unilateral',
  'step': 'unilateral',
};

/// Movement nouns: two names that each have one and share none are different exercises (a leg raise is not a crunch).
const _coreNouns = {
  'press', 'row', 'curl', 'fly', 'raise', 'extension', 'squat', 'lunge', 'deadlift', 'pulldown', 'pushdown', 'pullover', 'shrug', 'crunch',
  'thrust', 'kickback', 'dip', 'twist', 'chop', 'abduction', 'adduction', 'pull', 'push', 'swing', 'crusher',
};

Set<String> coreNouns(String name) => {
      for (final t in MediaMatcher.normalizeTokens(name.toLowerCase().replaceAll(RegExp(r'lying triceps (press|extension)'), 'skull crusher')))
        if (_coreNouns.contains(t)) t
    };

/// The movement-changing words of a name, after synonyms.
Set<String> modifierTokens(String name) {
  // "Side lateral raise" is a lateral raise, "palms-down" is the reverse grip, a "front lat pulldown" is the ordinary one.
  final n = name.toLowerCase().replaceAll('side lateral', 'lateral').replaceAll('palms-down', 'reverse').replaceAll('palms down', 'reverse').replaceAll('front lat pulldown', 'lat pulldown');
  final out = <String>{};
  for (final t in MediaMatcher.normalizeTokens(n)) {
    final c = _synonyms[t] ?? t;
    if (_modifiers.contains(c)) out.add(c);
  }
  return out;
}

/// The modifiers one name has and the other lacks.
Set<String> modifierDiff(String a, String b) => _diff(modifierTokens(a), modifierTokens(b));

Set<String> _diff(Set<String> a, Set<String> b) => a.difference(b).union(b.difference(a));

enum GifVerdict { ok, noGif, wrongEquipment, wrongMovement }

/// Strict rule for a GIF: it is shown only when it is the same movement on the same equipment. Missing equipment on our side
/// ("other") is not a reason to refuse; the name has to carry it.
GifVerdict gifVerdict({
  required String name,
  required String? equipment,
  required EdbExercise edb,
  required MediaMatcher matcher,
}) {
  if (MediaMatcher.equipmentScore(equipment, edb.equipments) < 1 && equipment != null && equipment.toLowerCase() != 'other') {
    return GifVerdict.wrongEquipment;
  }
  if (_diff(modifierTokens(name), modifierTokens(edb.name)).isNotEmpty) return GifVerdict.wrongMovement;
  final a = coreNouns(name), b = coreNouns(edb.name);
  if (a.isNotEmpty && b.isNotEmpty && a.intersection(b).isEmpty) return GifVerdict.wrongMovement;
  if (matcher.nameSimilarity(MediaMatcher.normalizeTokens(name).toSet(), edb) < 0.45) return GifVerdict.wrongMovement;
  return GifVerdict.ok;
}

