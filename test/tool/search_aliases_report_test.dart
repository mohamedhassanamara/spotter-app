// Writes docs/SEARCH_ALIASES.md: every alias the library search knows. ALIAS_REPORT=1 flutter test test/tool/search_aliases_report_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/features/library/domain/exercise_aliases.dart';

Map<String, dynamic> _json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('search aliases → docs/SEARCH_ALIASES.md', () {
    final aliases = buildAliases(
      myRoutines: _json('assets/programs/my_routines.json'),
      canonicalProgram: _json('assets/programs/min_max_canonical.json'),
      liftoffMap: _json('assets/liftoff_name_map.json'),
    );
    final out = StringBuffer('# Library search aliases\n\nOther names the library search also finds an exercise under (besides its own name and the names in my routines/sessions, '
        'which are added live). Source: my_routines.json (my name, program name), min_max_canonical.json (program slot and its substitutions), liftoff_name_map.json.\n\n'
        '| Library exercise | Also found as |\n|---|---|\n');
    for (final id in aliases.keys.toList()..sort()) {
      out.writeln('| `$id` | ${(aliases[id]!.toList()..sort()).join('; ')} |');
    }
    File('docs/SEARCH_ALIASES.md').writeAsStringSync(out.toString());
  }, skip: Platform.environment['ALIAS_REPORT'] == null ? 'set ALIAS_REPORT=1' : false);
}
