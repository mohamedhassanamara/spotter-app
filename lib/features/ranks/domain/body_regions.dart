import '../../../core/domain/muscles.dart';

/// How a body-map part is drawn.
enum RegionRole {
  /// One of the 20 ranking muscles.
  muscle,

  /// Neck and tibialis: real muscles we don't rank, rendered neutral.
  neutral,

  /// Head, hair, hands, feet, knees, ankles: the silhouette.
  structure,
}

/// Body-map slugs (react-native-body-highlighter) that are one muscle as drawn. Chest, deltoids,
/// upper back and gluteal are split by [BodyMap] (see `body_map.dart`).
const Map<String, Muscle> bodySlugToMuscle = {
  'abs': Muscle.abdominals,
  'obliques': Muscle.obliques,
  'biceps': Muscle.biceps,
  'triceps': Muscle.triceps,
  'forearm': Muscle.forearms,
  'trapezius': Muscle.traps,
  'lower-back': Muscle.lowerBack,
  'quadriceps': Muscle.quadriceps,
  'hamstring': Muscle.hamstrings,
  'calves': Muscle.calves,
  'adductors': Muscle.adductors,
};

/// Slugs whose paths are split or assigned by shape.
const Set<String> splitBodySlugs = {'chest', 'deltoids', 'upper-back', 'gluteal'};

const Set<String> neutralBodySlugs = {'neck', 'tibialis'};

RegionRole roleForSlug(String slug) {
  if (bodySlugToMuscle.containsKey(slug) || splitBodySlugs.contains(slug)) return RegionRole.muscle;
  if (neutralBodySlugs.contains(slug)) return RegionRole.neutral;
  return RegionRole.structure;
}

/// Which view (front/back) shows a muscle best, for thumbnails and deep links.
bool muscleOnBack(Muscle m) => const {
      Muscle.triceps,
      Muscle.hamstrings,
      Muscle.glutes,
      Muscle.calves,
      Muscle.abductors,
      Muscle.rearDelt,
      Muscle.lats,
      Muscle.upperBack,
      Muscle.traps,
      Muscle.lowerBack,
    }.contains(m);

/// Working sets in the last 7 days vs. the weekly average of the 4 weeks before.
class GroupVolume {
  const GroupVolume({required this.recentSets, required this.weeklyAverage});
  final int recentSets;
  final double weeklyAverage;

  /// recent ÷ average; null when there's no 4-week baseline.
  double? get ratio => weeklyAverage > 0 ? recentSets / weeklyAverage : null;
}

enum VolumeLevel { none, under, low, onTrack, high, new_ }

/// Heatmap buckets. Under < 50 % of the usual week, low < 85 %, on track ≤ 150 %, high above that
/// (the same 1.5× that triggers the readiness load modifier).
VolumeLevel volumeLevel(GroupVolume? v) {
  if (v == null || (v.recentSets == 0 && v.weeklyAverage == 0)) return VolumeLevel.none;
  final r = v.ratio;
  if (r == null) return VolumeLevel.new_;
  if (r < 0.5) return VolumeLevel.under;
  if (r < 0.85) return VolumeLevel.low;
  if (r <= 1.5) return VolumeLevel.onTrack;
  return VolumeLevel.high;
}
