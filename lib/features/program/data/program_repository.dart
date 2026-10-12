import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/db/database.dart';
import '../../../core/domain/dates.dart';
import '../../../core/domain/training.dart';
import '../../../core/settings/app_settings.dart';
import '../../library/domain/exercise_info.dart';
import '../domain/program.dart';

const String programStartKey = 'program_start_monday';
const String routinesInstalledKey = 'program_routines_installed';

class ProgramRepository {
  ProgramRepository(this._db);
  final AppDatabase _db;

  static Program? _cache;

  static Future<Program> load() async =>
      _cache ??= Program.fromJson(jsonDecode(await rootBundle.loadString('assets/programs/min_max_phase2.json')) as Map<String, dynamic>);

  static Future<Map<String, dynamic>> loadMyRoutines() async =>
      jsonDecode(await rootBundle.loadString('assets/programs/my_routines.json')) as Map<String, dynamic>;

  /// Monday of program week 1, or null if not set.
  Future<DateTime?> startMonday() async {
    final raw = await _db.getSetting(programStartKey);
    return raw == null ? null : parseDayKey(raw);
  }

  /// Sets the current program week by back-computing week 1's Monday.
  Future<void> setCurrentWeek(int week, {required DateTime now}) =>
      _db.putSetting(programStartKey, dayKey(startMondayForWeek(week: week, now: now)));

  /// Replaces all routines with the owner's program routines (sessions are kept; they don't
  /// reference routine rows). Rows missing from the catalogue are skipped and returned.
  Future<List<String>> installMyRoutines({
    required Program program,
    required Map<String, dynamic> definition,
    required Map<String, ExerciseInfo> catalog,
    required SettingsModel settings,
    required DateTime now,
  }) async {
    final skipped = <String>[];
    await _db.transaction(() async {
      await _db.delete(_db.routineExercises).go();
      await _db.delete(_db.routines).go();
      var rPos = 0;
      for (final r in (definition['routines'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final routineId = await _db.into(_db.routines).insert(RoutinesCompanion.insert(
              name: r['name'] as String,
              position: Value(rPos++),
              createdAt: now,
              programDay: Value(r['day'] as String),
            ));
        var pos = 0;
        for (final e in (r['exercises'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          final id = e['exercise_id'] as String;
          final slots = (e['program_slots'] as List<dynamic>).cast<String>();
          final first = program.slot(slots.first);
          if (catalog[id] == null || first == null) {
            skipped.add(e['name'] as String);
            continue;
          }
          final week1 = first.week(2); // a normal training week for the default RIR shown in the editor
          await _db.into(_db.routineExercises).insert(RoutineExercisesCompanion.insert(
                routineId: routineId,
                exerciseId: id,
                position: pos++,
                repMin: first.repRange.min,
                repMax: first.repRange.max,
                targetSets: (e['sets'] as num).toInt(),
                restSeconds: first.rest?.maxSeconds ?? 0,
                targetRir: Value(week1.rir.firstOrNull ?? settings.defaultRir),
                programSlots: Value(jsonEncode(slots)),
                programRelation: Value(e['relation'] as String?),
                programExercise: Value(e['program_exercise'] as String?),
                displayName: Value(e['name'] as String?),
              ));
        }
      }
      await _db.putSetting(routinesInstalledKey, '${definition['schema_version'] ?? 1}');
    });
    return skipped;
  }
}

/// Program slots stored on a routine or session row.
List<String> decodeSlots(String? raw) => raw == null ? const [] : (jsonDecode(raw) as List<dynamic>).cast<String>();

RepRange? rangeOf(int? min, int? max) => (min == null || max == null) ? null : RepRange(min, max);
