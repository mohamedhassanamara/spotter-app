import '../../../core/domain/muscle_group.dart';

/// How a body-map region is drawn.
enum RegionRole {
  /// One of the 12 ranking groups.
  muscle,

  /// A real muscle we don't rank (adductors, lower back, neck, tibialis): rendered neutral.
  neutral,

  /// Head, hair, hands, feet, knees, ankles: the silhouette.
  structure,
}

/// Mapping from the body-map SVG slugs (react-native-body-highlighter) to our ranking groups.
const Map<String, MuscleGroup> bodySlugToGroup = {
  'chest': MuscleGroup.chest,
  'abs': MuscleGroup.abs,
  'obliques': MuscleGroup.abs,
  'biceps': MuscleGroup.biceps,
  'triceps': MuscleGroup.triceps,
  'forearm': MuscleGroup.forearms,
  'deltoids': MuscleGroup.shoulders,
  'trapezius': MuscleGroup.traps,
  'upper-back': MuscleGroup.back,
  'gluteal': MuscleGroup.glutes,
  'quadriceps': MuscleGroup.quads,
  'hamstring': MuscleGroup.hamstrings,
  'calves': MuscleGroup.calves,
};

const Set<String> neutralBodySlugs = {'adductors', 'lower-back', 'neck', 'tibialis'};

RegionRole roleForSlug(String slug) {
  if (bodySlugToGroup.containsKey(slug)) return RegionRole.muscle;
  if (neutralBodySlugs.contains(slug)) return RegionRole.neutral;
  return RegionRole.structure;
}

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
