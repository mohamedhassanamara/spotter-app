import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/domain/gym.dart';

final equipmentSyncProvider = Provider<EquipmentSync>((ref) => EquipmentSync(ref));

/// Weight steps / gym equipment changed: the running workout is the one thing that may re-plan on it. The coach the workout was planned with
/// keeps everything (readiness, recovery, freezes) but takes the new gym, and every exercise whose grid changed re-snaps its not-yet-completed
/// sets (completed sets are never touched). Outside a workout nothing is stored: the next plan reads the gym fresh.
class EquipmentSync {
  EquipmentSync(this._ref);
  final Ref _ref;

  Future<int> onGymChanged(GymEquipment next) async {
    final repo = _ref.read(sessionRepositoryProvider);
    final session = await repo.loadActive();
    if (session == null) return 0;
    final catalog = await _ref.read(catalogProvider.future);
    final before = await _ref.read(workoutCoachProvider)(session.session.id);
    if (before.gym.encode() == next.encode()) return 0;
    final coach = before.withGym(next);
    _ref.read(frozenCoachProvider.notifier).freeze(session.session.id, coach);
    var changed = 0;
    for (final ex in session.exercises) {
      final info = catalog[ex.row.exerciseId];
      if (info == null || ex.sets.every((s) => s.completed)) continue;
      final oldGrid = before.gridFor(info), grid = coach.gridFor(info);
      if (_sameGrid(oldGrid, grid)) continue;
      // The sets keep their target, snapped to the nearest load of the new grid: no new plan, so nothing else about the workout moves.
      changed += await repo.applyEquipmentChange(ex, grid: grid);
    }
    return changed;
  }

  static bool _sameGrid(WeightGrid a, WeightGrid b) =>
      a.maxLoad == b.maxLoad && a.values.length == b.values.length && [for (var i = 0; i < a.values.length; i++) (a.values[i] - b.values[i]).abs() < 0.005].every((x) => x);
}
