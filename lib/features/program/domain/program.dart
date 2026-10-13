import 'dart:math' as math;

import '../../../core/domain/equipment.dart';
import '../../../core/domain/training.dart';
import '../../tutorials/domain/youtube.dart';

/// Pure model of a training program extracted from its source (see docs/program/SCHEMA.md).

/// The owner runs one fixed weekly template, not the 12-week plan: the app reads only the canonical
/// week (week 5 of the PDF, built by tool/program/canonical_week.py into
/// assets/programs/min_max_canonical.json). No intro/deload easing, no week tracking, and the program
/// never creates drop sets, myo-reps or holds; those are added by hand in the logger.

/// Warm-up sets for a slot: the higher count for the day's first exercise and for compounds,
/// the lower count for isolation work (the owner trains to failure and wants to get to work sets fast).
int warmupCountFor(ProgramSlot slot, {required bool firstOfDay, required bool compound}) =>
    (firstOfDay || compound) ? slot.warmupSets.max : slot.warmupSets.min;

class IntRange {
  const IntRange(this.min, this.max);
  final int min;
  final int max;

  static IntRange fromJson(Map<String, dynamic> j) => IntRange((j['min'] as num).toInt(), (j['max'] as num).toInt());

  @override
  String toString() => min == max ? '$min' : '$min–$max';
}

class RestPrescription {
  const RestPrescription({required this.minSeconds, required this.maxSeconds, required this.text});
  final int minSeconds;
  final int maxSeconds;
  final String text;
}

class TechniqueDef {
  const TechniqueDef({required this.id, required this.name, required this.when, required this.description, this.drops, this.dropPct});
  final String id;
  final String name;
  final String when;
  final String description;
  final int? drops;
  final int? dropPct;
}

class WarmupStep {
  const WarmupStep(this.pct, this.reps);
  final int pct;
  final IntRange reps;
}

class ProgramSlot {
  const ProgramSlot({
    required this.id,
    required this.day,
    required this.exercise,
    required this.superset,
    required this.warmupSets,
    required this.workingSets,
    required this.repRange,
    required this.perSide,
    required this.repText,
    required this.rest,
    required this.substitutions,
    required this.notes,
    required this.rir0AttemptFailure,
    required this.rir,
    this.videos = const {},
  });

  final String id;
  final String day;
  final String exercise;

  /// Jeff Nippard's demo per name (the slot's exercise and each substitution), from the PDF's links.
  final Map<String, YouTubeRef> videos;

  /// "S1", "S2"… or null.
  final String? superset;
  final IntRange warmupSets;
  final int workingSets;
  final RepRange repRange;
  final bool perSide;
  final String repText;

  /// Null for the first exercise of a superset (go straight to the partner).
  final RestPrescription? rest;
  final List<String> substitutions;
  final String notes;

  /// False for exercises where RIR 0 means "no rep left, but don't attempt and fail it".
  final bool rir0AttemptFailure;
  /// Target RIR per working set in the canonical week (0 = to failure; null = no target, "-").
  final List<int?> rir;
}

MapEntry<String, YouTubeRef>? _ref(String name, String url) {
  final r = parseYouTubeLink(url);
  return r == null ? null : MapEntry(name, r);
}

class ProgramDay {
  const ProgramDay({required this.id, required this.name, required this.slots});
  final String id;
  final String name;
  final List<ProgramSlot> slots;
}

class Program {
  Program({
    required this.id,
    required this.name,
    required this.canonicalWeek,
    required this.weekLayout,
    required this.days,
    required this.techniques,
    required this.warmupByCount,
    required this.progressionRule,
    required this.progressionFallback,
  }) : _slots = {for (final d in days) for (final s in d.slots) s.id: s};

  final String id;
  final String name;

  /// Week of the PDF the fixed template was taken from (5).
  final int canonicalWeek;
  final List<String> weekLayout;
  final List<ProgramDay> days;
  final Map<String, TechniqueDef> techniques;
  final Map<int, List<WarmupStep>> warmupByCount;
  final String progressionRule;
  final String progressionFallback;

  final Map<String, ProgramSlot> _slots;

  ProgramSlot? slot(String id) => _slots[id];

  /// ISO weekdays (Monday = 1) the program schedules as rest.
  Set<int> get plannedRestWeekdays => {
        for (var i = 0; i < weekLayout.length; i++)
          if (weekLayout[i] == 'Rest') i + 1,
      };

  /// Training days per week in the program's layout.
  int get sessionsPerWeek => weekLayout.where((d) => d != 'Rest').length;

  factory Program.fromJson(Map<String, dynamic> j) {
    final p = j['program'] as Map<String, dynamic>;
    final method = j['method'] as Map<String, dynamic>;
    final tech = <String, TechniqueDef>{};
    (method['techniques'] as Map<String, dynamic>).forEach((id, raw) {
      final t = raw as Map<String, dynamic>;
      tech[id] = TechniqueDef(
        id: id,
        name: t['name'] as String,
        when: t['when'] as String,
        description: t['description'] as String,
        drops: (t['drops'] as num?)?.toInt(),
        dropPct: (t['drop_pct'] as num?)?.toInt(),
      );
    });
    final warm = <int, List<WarmupStep>>{};
    final specific = (method['warmup'] as Map<String, dynamic>)['exercise_specific'] as Map<String, dynamic>;
    (specific['by_count'] as Map<String, dynamic>).forEach((k, v) {
      warm[int.parse(k)] = [
        for (final s in (v as List<dynamic>).cast<Map<String, dynamic>>())
          WarmupStep((s['pct'] as num).toInt(), IntRange.fromJson(s['reps'] as Map<String, dynamic>)),
      ];
    });
    final days = <ProgramDay>[];
    for (final d in (j['days'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final dayId = d['id'] as String;
      days.add(ProgramDay(
        id: dayId,
        name: d['name'] as String,
        slots: [
          for (final s in (d['slots'] as List<dynamic>).cast<Map<String, dynamic>>())
            () {
              final rr = s['rep_range'] as Map<String, dynamic>;
              final rest = s['rest'] as Map<String, dynamic>?;
              return ProgramSlot(
                id: s['slot_id'] as String,
                day: dayId,
                exercise: s['exercise'] as String,
                superset: s['superset'] as String?,
                warmupSets: IntRange.fromJson(s['warmup_sets'] as Map<String, dynamic>),
                workingSets: (s['working_sets'] as num).toInt(),
                repRange: RepRange((rr['min'] as num).toInt(), (rr['max'] as num).toInt()),
                perSide: rr['per_side'] as bool? ?? false,
                repText: rr['text'] as String,
                rest: rest == null
                    ? null
                    : RestPrescription(
                        minSeconds: (rest['min_s'] as num).toInt(),
                        maxSeconds: (rest['max_s'] as num).toInt(),
                        text: rest['text'] as String,
                      ),
                substitutions: (s['substitutions'] as List<dynamic>).cast<String>(),
                videos: Map.fromEntries([
                  if (s['video'] case {'url': final String url}) ?_ref(s['exercise'] as String, url),
                  for (final e in ((s['substitution_videos'] as Map<String, dynamic>?) ?? const {}).entries)
                    if (e.value case {'url': final String url}) ?_ref(e.key, url),
                ]),
                notes: s['notes'] as String? ?? '',
                rir0AttemptFailure: s['rir0_attempt_failure'] as bool? ?? true,
                rir: [for (final r in (s['rir'] as List<dynamic>)) (r as num?)?.toInt()],
              );
            }(),
        ],
      ));
    }
    final prog = method['progression'] as Map<String, dynamic>;
    return Program(
      id: p['id'] as String,
      name: p['name'] as String,
      canonicalWeek: (p['canonical_week'] as num?)?.toInt() ?? 5,
      weekLayout: (p['week_layout'] as List<dynamic>).cast<String>(),
      days: days,
      techniques: tech,
      warmupByCount: warm,
      progressionRule: prog['rule'] as String,
      progressionFallback: prog['fallback'] as String,
    );
  }
}

/// One working set as prescribed for a given week.
class SetPrescription {
  const SetPrescription({
    required this.slotId,
    required this.repRange,
    required this.targetRir,
    required this.restSeconds,
    required this.rir0AttemptFailure,
  });

  final String slotId;
  final RepRange repRange;
  final int? targetRir;

  final int? restSeconds;
  final bool rir0AttemptFailure;

  SetPrescription withRange(RepRange r) => SetPrescription(
        slotId: slotId,
        repRange: r,
        targetRir: targetRir,
        restSeconds: restSeconds,
        rir0AttemptFailure: rir0AttemptFailure,
      );
}

/// Expands a routine row (owner's set count spread over one or more program slots) into
/// per-set prescriptions (canonical week). Sets fill the first slot's working sets, then the next.
/// If the owner has more sets than the slots provide, extra sets repeat the last slot's last set
/// (no technique); fewer sets just take the first ones.
List<SetPrescription> prescribeSets({required Program program, required List<String> slotIds, required int sets}) {
  final out = <SetPrescription>[];
  final slots = [for (final id in slotIds) ?program.slot(id)];
  if (slots.isEmpty) return out;
  for (final s in slots) {
    for (var i = 0; i < s.workingSets && out.length < sets; i++) {
      out.add(SetPrescription(
        slotId: s.id,
        repRange: s.repRange,
        targetRir: i < s.rir.length ? s.rir[i] : null,
        restSeconds: s.rest?.maxSeconds,
        rir0AttemptFailure: s.rir0AttemptFailure,
      ));
    }
  }
  while (out.length < sets) {
    final last = out.last;
    out.add(SetPrescription(
      slotId: last.slotId,
      repRange: last.repRange,
      targetRir: last.targetRir,
      restSeconds: last.restSeconds,
      rir0AttemptFailure: last.rir0AttemptFailure,
    ));
  }
  return out;
}

class WarmupSet {
  const WarmupSet({required this.weight, required this.reps, required this.pct, required this.repRange});
  final double weight;
  final int reps;
  final int pct;
  final IntRange repRange;
}

/// Exercise-specific warm-up pyramid from the program, as % of today's working weight,
/// rounded to the equipment increment (never below one increment when the working weight is loaded).
/// Reps are prefilled at the low end of each step's range.
List<WarmupSet> warmupSets({required Program program, required int count, required double workingWeight, required double increment}) {
  if (count <= 0) return const [];
  final steps = program.warmupByCount[math.min(count, program.warmupByCount.keys.reduce(math.max))] ?? const [];
  return [
    for (final s in steps)
      WarmupSet(
        weight: workingWeight <= 0 ? 0 : math.max(increment, roundToIncrement(workingWeight * s.pct / 100, increment)),
        reps: s.reps.min,
        pct: s.pct,
        repRange: s.reps,
      ),
  ];
}

