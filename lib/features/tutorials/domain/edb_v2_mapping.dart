import 'dart:math' as math;

import '../../../core/domain/muscles.dart';
import '../../library/domain/exercise_info.dart';
import 'media_matcher.dart';

/// What we search ExerciseDB V2 for: the library name without dataset suffixes
/// ("Barbell Bench Press - Medium Grip" → "Barbell Bench Press", "Hyperextensions (Back Extensions)" →
/// "Hyperextensions"). One search per exercise.
String edbQueryFor(ExerciseInfo info) {
  var q = info.name;
  q = q.replaceAll(RegExp(r'\s*\(.*?\)'), '');
  q = q.split(' - ').first;
  return q.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Words a V2 exercise name uses for each dataset equipment value.
const Map<String, Set<String>> _equipmentWords = {
  'barbell': {'barbell', 'bar'},
  'e-z curl bar': {'ez', 'barbell', 'bar'},
  'dumbbell': {'dumbbell'},
  'cable': {'cable', 'rope', 'pulley'},
  'machine': {'lever', 'machine', 'smith', 'sled', 'assisted', 'leverage'},
  'kettlebells': {'kettlebell'},
  'bands': {'band', 'resistance'},
};

final Set<String> _allEquipmentWords = {for (final s in _equipmentWords.values) ...s};

/// 1 when the candidate names our equipment, 0.5 when it names none, 0 when it names other equipment.
/// [ours] is the dataset's equipment ("barbell", "cable", "machine", "body only"…).
double equipmentScore(String? ours, String candidateName) {
  final words = MediaMatcher.normalizeTokens(candidateName).toSet();
  final mentioned = words.intersection(_allEquipmentWords);
  final mine = _equipmentWords[ours?.toLowerCase().trim()] ?? const <String>{};
  if (mentioned.isEmpty) return mine.isEmpty ? 1 : 0.5;
  if (mine.isEmpty) return 0.3; // bodyweight / other vs a loaded variant
  return mentioned.intersection(mine).isNotEmpty ? 1 : 0;
}

/// Dice similarity of normalised name tokens (the media matcher's normalisation: plurals, pull-up
/// spellings, stop-words), ignoring equipment words, which [equipmentScore] scores separately.
double nameScore(String ours, String theirs) {
  Set<String> t(String s) => MediaMatcher.normalizeTokens(s).toSet().difference(_allEquipmentWords);
  final a = t(ours), b = t(theirs);
  if (a.isEmpty || b.isEmpty) return 0;
  return 2 * a.intersection(b).length / (a.length + b.length);
}

/// V2 muscle names ("Pectoralis Major Clavicular Head", "Deltoid Posterior"…) → our 20 muscles.
Muscle? muscleForV2(String name) {
  final n = name.toLowerCase();
  bool has(String s) => n.contains(s);
  if (has('pectoralis') || has('pectoral')) {
    if (has('clavicular')) return Muscle.upperChest;
    return Muscle.lowerChest; // sternal / abdominal head, or unspecified
  }
  if (has('deltoid')) {
    if (has('anterior') || has('front')) return Muscle.frontDelt;
    if (has('lateral') || has('middle') || has('medial')) return Muscle.middleDelt;
    if (has('posterior') || has('rear')) return Muscle.rearDelt;
    return Muscle.frontDelt;
  }
  if (has('latissimus') || n == 'lats') return Muscle.lats;
  if (has('trapezius')) return has('upper') || n == 'trapezius' ? Muscle.traps : Muscle.upperBack;
  if (has('rhomboid') || has('infraspinatus') || has('teres') || has('rotator')) return Muscle.upperBack;
  if (has('erector') || has('lower back') || has('quadratus')) return Muscle.lowerBack;
  if (has('gluteus maximus') || n == 'glutes' || n == 'gluteus') return Muscle.glutes;
  if (has('gluteus medius') || has('gluteus minimus') || has('tensor fasciae') || has('abductor')) return Muscle.abductors;
  if (has('adductor') || has('gracilis') || has('pectineus')) return Muscle.adductors;
  if (has('quadriceps') || has('rectus femoris') || has('vastus')) return Muscle.quadriceps;
  if (has('hamstring') || has('biceps femoris') || has('semitendinosus') || has('semimembranosus')) return Muscle.hamstrings;
  if (has('gastrocnemius') || has('soleus') || has('calf') || has('calves')) return Muscle.calves;
  if (has('triceps')) return Muscle.triceps;
  if (has('biceps') || has('brachialis')) return Muscle.biceps;
  if (has('brachioradialis') || has('wrist') || has('forearm') || has('flexor') || has('extensor')) return Muscle.forearms;
  if (has('oblique')) return Muscle.obliques;
  if (has('rectus abdominis') || has('abdomin') || has('transverse')) return Muscle.abdominals;
  return null;
}

/// Target 1.0, secondary 0.3, per our muscle (strongest wins).
MuscleTargets targetsFromV2({required List<String> target, required List<String> secondary}) {
  final out = <Muscle, double>{};
  for (final m in secondary) {
    final x = muscleForV2(m);
    if (x != null) out[x] = math.max(out[x] ?? 0, 0.3);
  }
  for (final m in target) {
    final x = muscleForV2(m);
    if (x != null) out[x] = 1.0;
  }
  return MuscleTargets(out);
}

class EdbCandidate {
  const EdbCandidate({required this.edbId, required this.name, required this.nameScore, required this.equipmentScore, this.muscleScore});
  final String edbId;
  final String name;
  final double nameScore;
  final double equipmentScore;

  /// 1 when the candidate's target muscles include one of ours as prime mover; null when not fetched.
  final double? muscleScore;

  /// Name 70 %, equipment 30 %; a muscle check (when fetched) moves it by ±0.1.
  double get score {
    final base = 0.7 * nameScore + 0.3 * equipmentScore;
    final m = muscleScore;
    return m == null ? base : (base + (m >= 1 ? 0.1 : -0.1)).clamp(0.0, 1.0);
  }

  EdbCandidate withMuscle(double m) =>
      EdbCandidate(edbId: edbId, name: name, nameScore: nameScore, equipmentScore: equipmentScore, muscleScore: m);

  Map<String, Object?> toJson() => {'id': edbId, 'name': name, 'score': double.parse(score.toStringAsFixed(3))};
}

List<EdbCandidate> scoreCandidates(ExerciseInfo info, Iterable<({String id, String name})> hits) {
  final query = edbQueryFor(info);
  final out = [
    for (final h in hits)
      EdbCandidate(edbId: h.id, name: h.name, nameScore: nameScore(query, h.name), equipmentScore: equipmentScore(info.equipment, h.name)),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// Auto-accept: at least [autoAccept] and clearly ahead of the runner-up. Otherwise it's queued for
/// review in the debug Media matching screen.
const double autoAccept = 0.85;
const double autoMargin = 0.08;

bool isConfident(List<EdbCandidate> ranked) {
  if (ranked.isEmpty) return false;
  final top = ranked.first.score;
  final second = ranked.length > 1 ? ranked[1].score : 0.0;
  return top >= autoAccept && top - second >= autoMargin;
}

/// Our prime movers vs the candidate's target muscles: 1 on any overlap.
double muscleAgreement(ExerciseInfo info, List<String> v2Targets) {
  final theirs = {for (final m in v2Targets) ?muscleForV2(m)};
  final ours = {for (final e in info.targets.weights.entries) if (e.value >= 1) e.key};
  if (theirs.isEmpty || ours.isEmpty) return 0.5;
  return theirs.intersection(ours).isNotEmpty ? 1 : 0;
}
