import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotter/core/domain/training.dart';
import 'package:spotter/features/coach/domain/suggestion_engine.dart';
import 'package:spotter/features/import/domain/liftoff.dart';
import 'package:spotter/features/import/domain/liftoff_mapping.dart';
import 'package:spotter/features/library/domain/exercise_info.dart';

ExerciseInfo ex(String id, String name) => ExerciseInfo(
      id: id,
      name: name,
      primaryMuscles: const ['chest'],
      secondaryMuscles: const [],
      equipment: 'machine',
      level: null,
      mechanic: 'compound',
      category: 'strength',
      instructions: const [],
      images: const [],
      isCustom: false,
      isFavorite: false,
      notes: null,
    );

void main() {
  group('csv', () {
    test('quoted fields, doubled quotes, CRLF, blank lines', () {
      final rows = parseCsv('a,b,c\r\n"x, y","say ""hi""",\r\n\r\n1,2,3');
      expect(rows, [
        ['a', 'b', 'c'],
        ['x, y', 'say "hi"', ''],
        ['1', '2', '3'],
      ]);
    });

    test('durations and dates', () {
      expect(parseLiftoffDuration('01 hours 20 minutes 14 seconds'), const Duration(hours: 1, minutes: 20, seconds: 14));
      expect(parseLiftoffDuration('00 hours 00 minutes 18 seconds'), const Duration(seconds: 18));
      expect(parseLiftoffDate('2026-06-12 08:44:09'), DateTime(2026, 6, 12, 8, 44, 9));
    });

    test('pounds to kilograms at full precision', () {
      expect(lbToKg(44.092452437), closeTo(20, 1e-4)); // Liftoff exports kg × 2.20462262; we divide by 2.20462 as specified
      expect(lbToKg(15.873282877), closeTo(7.2, 1e-4));
    });
  });

  group('notes', () {
    test('N*range/range expands per set, last range repeats', () {
      final n = parseNote('2*6-8/20');
      expect(n.ranges, const [RepRange(6, 8), RepRange(6, 8), RepRange(20, 20)]);
      expect(n.rangeFor(3), const RepRange(20, 20));
    });

    test('trailing technique letters, per leg, pause, failure', () {
      expect(parseNote('6-8   D').techniqueLetter, 'D');
      expect(parseNote('4-6. M').ranges, const [RepRange(4, 6)]);
      expect(parseNote('4-6. M').techniqueLetter, 'M');
      expect(parseNote('10 per leg').perSide, isTrue);
      expect(parseNote('10 per leg').ranges, const [RepRange(10, 10)]);
      expect(parseNote('Pause').pause, isTrue);
      expect(parseNote('Failure').failure, isTrue);
      expect(parseNote('Failure').ranges, isEmpty);
      expect(parseNote('').rangeFor(0), isNull);
    });
  });

  group('parse', () {
    final p = parseLiftoff(File('test/fixtures/liftoff_sample.csv').readAsStringSync());

    test('groups rows by Date into sessions, sets ordered by Set Order', () {
      expect(p.sessions.length, 2);
      final first = p.sessions.first;
      expect(first.start, DateTime(2026, 9, 1, 8));
      expect(first.end, DateTime(2026, 9, 1, 9, 10));
      expect(first.exercises.map((e) => e.name), ['Chest Press', 'Machine Chest Fly', 'Chest Supported T Bar Row']);
      final pull = p.sessions.last.exercises.first;
      expect(pull.sets.map((s) => s.reps), [8, 7], reason: 'Set Order 0 first even if listed second');
      expect(p.sessions.first.exercises.last.sets.single.rpe, 8);
      expect(p.setCount, 9);
    });

    test('skips cardio/timed rows and the empty workout row', () {
      expect(p.skipped.map((s) => s.exercise), ['Walking', '']);
      expect(p.skipped.first.reason, startsWith('cardio/timed'));
    });

    test('rejects files that are not a Liftoff export', () {
      expect(() => parseLiftoff('Date,Exercise\n1,2'), throwsFormatException);
    });
  });

  group('mapping', () {
    final catalog = {
      for (final e in [
        ex('Leverage_Chest_Press', 'Leverage Chest Press'),
        ex('Butterfly', 'Butterfly'),
        ex('Lying_T-Bar_Row', 'Lying T-Bar Row'),
        ex('Leg_Extensions', 'Leg Extensions'),
        ex('Cable_Crunch', 'Cable Crunch'),
        ex('sp_assisted_pull_up_machine', 'Assisted Pull-Up (Machine)'),
      ])
        e.id: e,
    };
    const routines = [
      RoutineName(name: 'Chest Press', exerciseId: 'Leverage_Chest_Press'),
      RoutineName(name: 'Chest Supported T-Bar Row', exerciseId: 'Lying_T-Bar_Row'),
    ];
    final map = LiftoffNameMap.parse('{"map": {"Assisted Pull Ups": "sp_assisted_pull_up_machine", '
        '"Dragon Flag": {"custom": {"name": "Dragon Flag", "primaryMuscles": ["abdominals"]}}}}');
    List<NameMapping> run(Map<String, int> names, {Map<String, String> manual = const {}}) =>
        mapLiftoffNames(setsByName: names, catalog: catalog, nameMap: map, routines: routines, manual: manual);

    test('name map, routine names (punctuation-insensitive), exact, fuzzy, custom, unmatched', () {
      final m = {
        for (final x in run({
          'Assisted Pull Ups': 3,
          'Chest Supported T Bar Row': 2,
          'Chest Press': 4,
          'Cable Crunch': 2,
          'Leg Extension': 3,
          'Dragon Flag': 1,
          'Zercher Good Morning Hop': 1,
        }))
          x.liftoffName: x,
      };
      expect(m['Assisted Pull Ups']!.method, MatchMethod.override);
      expect(m['Chest Supported T Bar Row']!.method, MatchMethod.routine);
      expect(m['Chest Supported T Bar Row']!.displayName, 'Chest Supported T-Bar Row');
      expect(m['Chest Press']!.exerciseId, 'Leverage_Chest_Press');
      expect(m['Cable Crunch']!.method, MatchMethod.exact);
      expect(m['Leg Extension']!.method, MatchMethod.exact, reason: 'plural-insensitive name');
      expect(m['Dragon Flag']!.method, MatchMethod.custom);
      expect(m['Dragon Flag']!.exerciseId, 'liftoff_dragon_flag');
      final u = m['Zercher Good Morning Hop']!;
      expect(u.method, MatchMethod.unmatched);
      expect(u.needsReview, isTrue);
      expect(u.exerciseId, 'liftoff_zercher_good_morning_hop');
    });

    test('a manual pick wins over everything', () {
      final m = run({'Zercher Good Morning Hop': 1}, manual: {'Zercher Good Morning Hop': 'Cable_Crunch'}).single;
      expect(m.method, MatchMethod.manual);
      expect(m.exerciseId, 'Cable_Crunch');
    });

    test('the bundled name map points at real exercises', () {
      final raw = File('assets/liftoff_name_map.json').readAsStringSync();
      final bundled = LiftoffNameMap.parse(raw);
      expect(bundled.ids, isNotEmpty);
      expect(bundled.customs.keys, contains('Dragon Flag'));
    });
  });

  test('display rounding: quarters exact, pound conversions to 0.5 kg', () {
    expect(formatKg(lbToKg(44.092452437)), '20');
    expect(formatKg(lbToKg(15.873282877)), '7');
    expect(formatKg(lbToKg(48.9)), '22');
    expect(formatKg(1.25), '1.25');
    expect(formatKg(82.5), '82.5');
    expect(formatKg(-25), '-25');
  });
}
