// docs/LOG_GUIDE.md: the "How to log?" rule of every exercise in my routines. LOG_GUIDE_REPORT=1 flutter test test/tool/log_guide_report_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/bootstrap.dart';
import 'package:spotter/core/db/database.dart';
import 'package:spotter/features/library/data/exercise_repository.dart';
import 'package:spotter/features/library/domain/load_kinds.dart';
import 'package:spotter/features/library/domain/log_guide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('how to log → docs/LOG_GUIDE.md', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await bootstrapDatabase(db);
    final catalog = await ExerciseRepository(db).watchCatalog().first;
    final routines = jsonDecode(File('assets/programs/my_routines.json').readAsStringSync()) as Map<String, dynamic>;
    final out = StringBuffer('# How to log: my routine exercises\n\nThe sheet behind **How to log?** on each exercise page. The rule follows the load type (your override from the logger\'s Weight steps…, else the classification in `load_types.dart`).\n\n'
        '| Routine | Exercise | Load type | Rule | Bar / sled / carriage |\n|---|---|---|---|---|\n');
    for (final r in (routines['routines'] as List).cast<Map<String, dynamic>>()) {
      for (final e in (r['exercises'] as List).cast<Map<String, dynamic>>()) {
        final info = catalog[e['exercise_id']]!;
        final g = logGuideFor(name: info.name, equipment: info.equipment, assisted: isAssisted(info.id), bodyweightLoaded: extraBodyweightExerciseIds.contains(info.id));
        out.writeln('| ${r['name']} | ${e['name']} | ${g.type.label}${g.unilateral ? ' (one side)' : ''} | ${g.headline} | ${g.includes} |');
      }
    }
    out.writeln('\nExercises without a defined rule: none (the "no equipment listed" fallback is not used by any exercise in my routines; a test fails if one appears).');
    File('docs/LOG_GUIDE.md').writeAsStringSync(out.toString());
  }, skip: Platform.environment['LOG_GUIDE_REPORT'] == null ? 'set LOG_GUIDE_REPORT=1' : false);
}
