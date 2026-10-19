import '../../../core/domain/dates.dart';
import '../../../core/domain/history.dart';
import '../../../core/domain/muscles.dart';
import '../../library/domain/exercise_info.dart';
import '../data/ranks_repository.dart';
import 'ranks.dart';

/// The ranks as they stood on one day (each from the 90 days before it, like today's ranks).
class RankPoint {
  const RankPoint({required this.date, required this.overall, required this.regions, required this.muscles});
  final DateTime date;
  final RankScore? overall;
  final Map<BodyRegion, RankScore> regions;
  final Map<Muscle, RankScore> muscles;
}

/// Overall, region and muscle rank over time, rebuilt from the whole history (the imported Liftoff sessions
/// included): one point per [stepDays] from the first logged session to [now], plus [now] itself. Exercises that
/// count today ([excluded] is today's switch state) count for every day, so the line shows what today's rules say
/// about the past. Days with nothing ranked yet are left out.
List<RankPoint> rankEvolution({
  required TrainingHistory history,
  required List<StrengthStandard> standards,
  required Map<String, ExerciseInfo> catalog,
  required BodyweightTimeline bodyweights,
  required Set<String> excluded,
  required DateTime now,
  Map<String, String> displayNames = const {},
  int stepDays = 7,
}) {
  if (history.sessions.isEmpty || bodyweights.isEmpty) return const [];
  final first = history.sessions.map((s) => s.startedAt).reduce((a, b) => a.isBefore(b) ? a : b);
  final days = <DateTime>[];
  for (var d = dateOnly(first); d.isBefore(dateOnly(now)); d = addDays(d, stepDays)) {
    days.add(d.add(const Duration(hours: 23, minutes: 59)));
  }
  days.add(now);
  final out = <RankPoint>[];
  for (final day in days) {
    final s = RanksRepository.compute(
      history: history,
      standards: standards,
      catalog: catalog,
      bodyweights: bodyweights,
      now: day,
      excluded: excluded,
      displayNames: displayNames,
    );
    if (s.overall == null) continue;
    out.add(RankPoint(
      date: day,
      overall: s.overall,
      regions: {for (final r in s.regions.values) if (r.score != null) r.region: r.score!},
      muscles: {for (final m in s.muscles.values) m.muscle: m.score},
    ));
  }
  return out;
}
