import '../../library/domain/exercise_info.dart';
import '../../library/domain/name_resolver.dart';
import '../../tutorials/domain/youtube.dart';
import 'program.dart';

/// Jeff Nippard's demo for one of my exercises, and the program name it belongs to.
class ProgramVideo {
  const ProgramVideo({required this.programName, required this.ref});
  final String programName;
  final YouTubeRef ref;
}

/// A routine row as far as videos care.
class RoutineVideoRow {
  const RoutineVideoRow({required this.exerciseId, required this.name, required this.relation, required this.programExercise, required this.slotIds});
  final String exerciseId;

  /// My name for it ("Lying Leg Curl").
  final String name;

  /// program | substitution | swap | extra
  final String? relation;
  final String? programExercise;
  final List<String> slotIds;
}

/// Normalised name; "reverse wrist curl" is the program's "wrist extension" (same movement).
String _key(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().replaceAll('reverse wrist curl', 'wrist extension');

/// exercise id → Jeff's video, only from the PDF's own links:
/// - a routine row that *is* the program exercise gets that exercise's video;
/// - a row that is one of the slot's listed substitutions gets that substitution's video (never the
///   main exercise's);
/// - my own swaps (Pendulum Squat, Straight Arm Pulldown, Decline Crunch) get nothing unless the program
///   lists them as a substitution;
/// - any other library exercise whose name clearly matches a program name (≥ 0.85) gets that video, so a
///   substitution picked mid-workout shows its demo too.
Map<String, ProgramVideo> programVideos({
  required Program program,
  required List<RoutineVideoRow> rows,
  required Map<String, ExerciseInfo> catalog,
}) {
  final out = <String, ProgramVideo>{};
  final swaps = <String>{};
  for (final r in rows) {
    final slots = [for (final id in r.slotIds) ?program.slot(id)];
    if (slots.isEmpty) continue;
    ProgramVideo? found;
    for (final slot in slots) {
      if (r.relation == 'program') {
        final ref = slot.videos[slot.exercise];
        if (ref != null) found = ProgramVideo(programName: slot.exercise, ref: ref);
      } else {
        // Substitution or swap: only a listed substitution with its own link.
        final name = _key(r.name);
        final libName = _key(catalog[r.exerciseId]?.name ?? '');
        for (final sub in slot.substitutions) {
          final k = _key(sub);
          if ((k == name || k == libName) && slot.videos[sub] != null) {
            found = ProgramVideo(programName: sub, ref: slot.videos[sub]!);
          }
        }
        if (found == null && r.relation == 'substitution' && r.programExercise != null) {
          // The routine names the substitution by my own wording; resolve the slot's substitutions to it.
          final resolver = ExerciseNameResolver([?catalog[r.exerciseId]]);
          for (final sub in slot.substitutions) {
            final m = resolver.resolve(sub, minScore: 0.85);
            if (m != null && slot.videos[sub] != null) found = ProgramVideo(programName: sub, ref: slot.videos[sub]!);
          }
        }
      }
      if (found != null) break;
    }
    if (r.relation == 'swap' && found == null) swaps.add(r.exerciseId);
    if (found != null) out.putIfAbsent(r.exerciseId, () => found!);
  }
  // Everything else in the library that clearly is a program exercise or substitution.
  final resolver = ExerciseNameResolver(catalog.values.where((e) => !e.isCustom));
  for (final day in program.days) {
    for (final slot in day.slots) {
      for (final e in slot.videos.entries) {
        final m = resolver.resolve(e.key, minScore: 0.85);
        if (m == null || swaps.contains(m.exercise.id)) continue;
        out.putIfAbsent(m.exercise.id, () => ProgramVideo(programName: e.key, ref: e.value));
      }
    }
  }
  return out;
}
