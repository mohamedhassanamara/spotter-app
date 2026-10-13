import 'dart:math' as math;

import '../../../core/domain/history.dart';
import '../../../core/domain/muscles.dart';
import '../../../core/domain/training.dart';
import 'recovery_config.dart';

enum RecoveryBand {
  ready('Ready'),
  recovering('Recovering'),
  fatigued('Fatigued');

  const RecoveryBand(this.label);
  final String label;

  static RecoveryBand of(double pct) => pct >= RecoveryConfig.readyAt
      ? ready
      : pct >= RecoveryConfig.recoveringAt
          ? recovering
          : fatigued;
}

/// Fatigue one set adds per unit of contribution.
double setFatigue(LoggedSet s) {
  if (!s.isWorking) return 0;
  if (s.isDrop) return RecoveryConfig.dropFactor;
  if (s.isMyo) return RecoveryConfig.myoFactor;
  if (s.isHold) return RecoveryConfig.holdFactor;
  final effort = Effort.fromRpe(s.rpe) ?? RecoveryConfig.unknownEffort;
  return RecoveryConfig.effortFactor[effort]!;
}

/// What's left of [fatigue] after [hours] for [muscle], at [speed] (readiness).
double decay(double fatigue, double hours, Muscle muscle, {double speed = 1}) {
  if (hours <= 0) return fatigue;
  return fatigue * math.pow(0.5, hours * speed / RecoveryConfig.halfLifeH(muscle)).toDouble();
}

/// 100 % = fully recovered.
double recoveryPct(double fatigue) => (100 * (1 - fatigue / RecoveryConfig.fullFatigue)).clamp(0, 100).toDouble();

/// Hours until the residual fatigue drops to the Ready band (0 when already Ready).
double hoursUntilReady(double fatigue, Muscle muscle, {double speed = 1}) {
  final target = RecoveryConfig.fullFatigue * (1 - RecoveryConfig.readyAt / 100);
  if (fatigue <= target) return 0;
  return RecoveryConfig.halfLifeH(muscle) / speed * (math.log(fatigue / target) / math.ln2);
}

class MuscleRecovery {
  const MuscleRecovery({required this.muscle, required this.fatigue, required this.pct, required this.hoursToReady, this.lastSession, this.lastHitAt});
  final Muscle muscle;
  final double fatigue;
  final double pct;
  final double hoursToReady;

  /// Most recent session that trained this muscle (null when none in the horizon).
  final String? lastSession;
  final DateTime? lastHitAt;

  RecoveryBand get band => RecoveryBand.of(pct);
}

class RecoveryState {
  const RecoveryState(this.muscles, {required this.speed});
  final Map<Muscle, MuscleRecovery> muscles;
  final double speed;

  MuscleRecovery of(Muscle m) => muscles[m]!;

  List<Muscle> inBand(RecoveryBand b) => [for (final m in Muscle.values) if (muscles[m]!.band == b) m];

  /// Home card line: "Ready: chest, triceps · Recovering: quads". Only trained muscles are named as
  /// Recovering/Fatigued; Ready lists those trained in the horizon (all fresh muscles would be noise).
  static String names(Iterable<Muscle> ms) => ms.map((m) => m.label.toLowerCase()).join(', ');
}

/// Recovery of all 20 muscles at [now] from finished sessions in [history]. [readinessBand] is today's
/// band ('green' | 'yellow' | 'red'; null → normal) and scales the recovery speed.
RecoveryState computeRecovery(TrainingHistory history, {required DateTime now, String? readinessBand}) {
  final speed = RecoveryConfig.readinessSpeed[readinessBand?.toLowerCase()] ?? 1.0;
  final fatigue = {for (final m in Muscle.values) m: 0.0};
  final last = <Muscle, (DateTime, String)>{};
  final from = now.subtract(RecoveryConfig.horizon);
  for (final s in history.sessions) {
    final at0 = s.endedAt ?? s.startedAt;
    if (at0.isBefore(from) || at0.isAfter(now)) continue;
    final perSession = <Muscle, double>{};
    for (final e in s.exercises) {
      for (final h in e.sets) {
        final f = setFatigue(h.set);
        if (f == 0) continue;
        final at = h.completedAt ?? at0;
        final hours = now.difference(at).inMinutes / 60;
        for (final w in e.targets.weights.entries) {
          final add = w.value * f;
          fatigue[w.key] = fatigue[w.key]! + decay(add, hours, w.key, speed: speed);
          perSession[w.key] = (perSession[w.key] ?? 0) + add;
        }
      }
    }
    for (final p in perSession.entries) {
      if (p.value < RecoveryConfig.hitThreshold) continue;
      final cur = last[p.key];
      if (cur == null || at0.isAfter(cur.$1)) last[p.key] = (at0, s.name);
    }
  }
  return RecoveryState({
    for (final m in Muscle.values)
      m: MuscleRecovery(
        muscle: m,
        fatigue: fatigue[m]!,
        pct: recoveryPct(fatigue[m]!),
        hoursToReady: hoursUntilReady(fatigue[m]!, m, speed: speed),
        lastSession: last[m]?.$2,
        lastHitAt: last[m]?.$1,
      ),
  }, speed: speed);
}

/// Primary muscles of a planned workout that are Fatigued now (for the start heads-up).
List<Muscle> fatiguedPrimaries(RecoveryState state, Iterable<MuscleTargets> exercises) {
  final primary = <Muscle>{for (final t in exercises) ...t.primary};
  return [for (final m in Muscle.values) if (primary.contains(m) && state.of(m).band == RecoveryBand.fatigued) m];
}
