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
  int dailyDays = 31,
}) {
  if (history.sessions.isEmpty || bodyweights.isEmpty) return const [];
  final first = history.sessions.map((s) => s.startedAt).reduce((a, b) => a.isBefore(b) ? a : b);
  final days = <DateTime>[];
  // One point per [stepDays] over the whole history, one per day over the last [dailyDays] so the Week and Month ranges have a line.
  final dailyFrom = addDays(dateOnly(now), -dailyDays);
  for (var d = dateOnly(first); d.isBefore(dailyFrom); d = addDays(d, stepDays)) {
    days.add(d.add(const Duration(hours: 23, minutes: 59)));
  }
  for (var d = dateOnly(first).isAfter(dailyFrom) ? dateOnly(first) : dailyFrom; d.isBefore(dateOnly(now)); d = addDays(d, 1)) {
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

/// The time range the rank chart shows.
enum EvolutionRange {
  week('Week', 7),
  month('Month', 30),
  threeMonths('3 Months', 90),
  year('Year', 365),
  all('All', null);

  const EvolutionRange(this.label, this.days);
  final String label;

  /// Length in days; null for everything.
  final int? days;
}

/// A value on the chart's time axis.
typedef EvolutionSample = ({DateTime date, double value});

/// The samples that fall in [range] ending at [now]. A range that starts between two samples gets a start point interpolated on the
/// line at its first day, so the line always spans the whole range; "All" starts at the first sample. Returns the range's start too.
({DateTime start, List<EvolutionSample> samples}) windowSamples(List<EvolutionSample> all, EvolutionRange range, DateTime now) {
  if (all.isEmpty) return (start: now, samples: const []);
  final days = range.days;
  if (days == null) return (start: all.first.date, samples: all);
  final start = now.subtract(Duration(days: days));
  final inside = [for (final p in all) if (!p.date.isBefore(start)) p];
  final before = all.where((p) => p.date.isBefore(start)).lastOrNull;
  if (before != null && inside.isNotEmpty && inside.first.date.isAfter(start)) {
    final next = inside.first;
    final span = next.date.difference(before.date).inSeconds;
    final f = span <= 0 ? 1.0 : start.difference(before.date).inSeconds / span;
    inside.insert(0, (date: start, value: before.value + (next.value - before.value) * f));
  }
  return (start: start, samples: inside);
}
