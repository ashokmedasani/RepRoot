import 'dart:convert';
import 'dart:io';

import 'package:reproot/shared/charts/analytics_types.dart';
import 'package:reproot/shared/charts/graph_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the Dart graph engine against fixtures generated from the REAL
/// TypeScript (mobile/src/app/shared/analytics/graph-engine.ts), compiled with
/// tsc and executed under node. Regenerate with:
///
///   `node tools/tsfix/gen.js > test/fixtures/graph_engine_ts.json`
///
/// Two behaviours differ from the TS **on purpose** — see FIX #1 / FIX #2 in
/// graph_engine.dart. Those are asserted explicitly at the bottom rather than
/// diffed, and the TS values are pinned there too so the divergence stays
/// deliberate and visible instead of drifting.

late final Map<String, dynamic> ts;

// Mirrors the fixture inputs in gen.js exactly.
const weight = FieldLike(key: 'weight', label: 'Body weight (kg)', fieldType: 'number');
const reps = FieldLike(key: 'reps', label: 'Reps', fieldType: 'number');
const mood = FieldLike(key: 'mood', label: 'Mood', fieldType: 'rating', scale: 5);
const moodBig = FieldLike(key: 'moodBig', label: 'Mood big', fieldType: 'rating', scale: 99);
const moodZero = FieldLike(key: 'moodZero', label: 'Mood zero', fieldType: 'rating', scale: 0);
const done = FieldLike(key: 'done', label: 'Workout done', fieldType: 'yes_no');
const meal = FieldLike(key: 'meal', label: 'Meal type', fieldType: 'dropdown');
const meal6 = FieldLike(key: 'meal6', label: 'Meal six', fieldType: 'dropdown');
const note = FieldLike(key: 'note', label: 'Note', fieldType: 'short_text');
const essay = FieldLike(key: 'essay', label: 'Essay', fieldType: 'long_text');
const noKey = FieldLike(label: 'No key field', fieldType: 'number');

final entries = <EntryLike>[
  const EntryLike(entryDate: '2026-07-10', entryTime: '08:30:00', answers: {
    'weight': '80', 'mood': '4', 'done': 'yes', 'meal': 'Breakfast', 'note': 'good', 'reps': '10',
  }),
  const EntryLike(entryDate: '2026-07-10', entryTime: '18:00:00', answers: {
    'weight': '0.5', 'mood': '2', 'done': 'no', 'meal': 'Dinner', 'note': 'good', 'reps': '5',
  }),
  const EntryLike(entryDate: '2026-07-11', entryTime: '09:00:00', answers: {
    'weight': '79.456', 'mood': '5', 'done': 'yes', 'meal': 'Breakfast', 'note': 'ok', 'reps': '8',
  }),
  const EntryLike(entryDate: '2026-07-12', entryTime: '07:15:00', answers: {
    'weight': '79', 'mood': '1', 'done': 'true', 'meal': 'Lunch', 'note': 'bad', 'reps': '12',
  }),
  const EntryLike(entryDate: '2026-07-13', entryTime: '', answers: {
    'weight': '', 'mood': '', 'done': '', 'meal': '', 'note': '', 'reps': 'abc',
  }),
  const EntryLike(entryDate: '2026-07-14', entryTime: '10:00:00', answers: {
    'weight': '78.5', 'mood': '3', 'done': '1', 'meal': 'Snack', 'note': 'ok', 'reps': '9',
  }),
];

final longEntries = [
  for (var d = 1; d <= 10; d++)
    EntryLike(
      entryDate: '2026-06-${d.toString().padLeft(2, '0')}',
      entryTime: '08:00:00',
      answers: {'weight': '${70 + d}'},
    ),
];

final dropdownEntries = [
  for (var i = 0; i < 6; i++)
    EntryLike(
      entryDate: '2026-06-0${i + 1}',
      entryTime: '08:00:00',
      answers: {'meal6': ['A', 'B', 'C', 'D', 'E', 'F'][i]},
    ),
];

const all = DateRange.all;

void main() {
  setUpAll(() {
    final file = File('test/fixtures/graph_engine_ts.json');
    ts = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  group('matches the TypeScript engine', () {
    test('fixtures came from a UTC-offset machine (context for FIX #2)', () {
      expect(ts['meta']['tzOffsetMinutes'], isA<int>());
    });

    test('fieldKey', () {
      expect(fieldKey(weight), ts['fieldKey']['withKey']);
      expect(fieldKey(noKey), ts['fieldKey']['withoutKey']);
    });

    test('extractUnit', () {
      expect(extractUnit('Body weight (kg)'), ts['extractUnit']['withUnit']);
      expect(extractUnit('Reps'), ts['extractUnit']['withoutUnit']);
      expect(extractUnit(''), ts['extractUnit']['empty']);
      expect(extractUnit('Volume (kg) total'), ts['extractUnit']['nested']);
    });

    test('sortByTime', () {
      final actual = sortByTime(entries)
          .map((e) => '${e.entryDate} ${e.entryTime}')
          .toList();
      expect(actual, (ts['sortByTime'] as List).cast<String>());
    });

    test('frequency (dropdown)', () {
      final actual = frequency(meal, entries);
      final expected = (ts['frequency'] as List)
          .map((p) => '${p['label']}=${p['value']}')
          .toList();
      expect(actual.map((p) => '${p.label}=${_n(p.value)}').toList(), expected);
    });

    test('frequency (short text)', () {
      final actual = frequency(note, entries);
      final expected = (ts['frequencyNote'] as List)
          .map((p) => '${p['label']}=${p['value']}')
          .toList();
      expect(actual.map((p) => '${p.label}=${_n(p.value)}').toList(), expected);
    });

    test('ratingDistribution', () {
      _expectPoints(ratingDistribution(mood, entries), ts['ratingDistribution']);
    });

    test('ratingDistribution clamps scale 99 -> 10', () {
      expect(ratingDistribution(moodBig, entries).length,
          (ts['ratingDistributionClampHigh'] as List).length);
    });

    test('ratingDistribution treats scale 0 as 5', () {
      expect(ratingDistribution(moodZero, entries).length,
          (ts['ratingDistributionScaleZero'] as List).length);
    });

    test('completionPercent', () {
      expect(completionPercent(done, entries), ts['completionPercent']);
    });

    test('decideChartForField picks the same chart kind for every field type', () {
      final decide = ts['decide'] as Map<String, dynamic>;
      String? kindOf(ChartSpec? spec) => spec?.kind.name;

      expect(kindOf(decideChartForField(weight, entries, all)), decide['numberShort']['kind']);
      expect(kindOf(decideChartForField(weight, longEntries, all)), decide['numberLong']['kind']);
      expect(kindOf(decideChartForField(mood, entries, all)), decide['rating']['kind']);
      expect(kindOf(decideChartForField(done, entries, all)), decide['yesNo']['kind']);
      expect(kindOf(decideChartForField(meal, entries, all)), decide['dropdownSmall']['kind']);
      expect(kindOf(decideChartForField(meal6, dropdownEntries, all)), decide['dropdownBig']['kind']);
      expect(kindOf(decideChartForField(note, entries, all)), decide['shortText']['kind']);
      expect(decideChartForField(essay, entries, all), isNull);
      expect(decide['longText'], isNull);
      expect(decideChartForField(weight, const [], all), isNull);
      expect(decide['numberEmpty'], isNull);
    });

    test('number series flips bar -> line above 8 points', () {
      expect(decideChartForField(weight, longEntries, all)!.kind, ChartKind.line);
      expect(longEntries.length, greaterThan(8));
    });

    test('dropdown flips pie -> hbar above 4 slices', () {
      expect(decideChartForField(meal6, dropdownEntries, all)!.kind, ChartKind.hbar);
    });

    test('buildFieldCharts drops fields with no chart', () {
      final actual = buildFieldCharts([weight, mood, done, meal, essay], entries, all)
          .map((s) => s.kind.name)
          .toList();
      final expected = (ts['buildFieldCharts'] as List)
          .map((s) => s['kind'] as String)
          .toList();
      expect(actual, expected);
    });

    test('rating summary card reports the same scale subtitle', () {
      // The value itself intentionally differs — see FIX #1 below.
      final cards = buildOverviewCards([mood], entries);
      final tsCard = (ts['buildOverviewCards'] as List)[1];
      expect(cards.single.meta!.subtitle, tsCard['meta']['subtitle']);
    });

    test('JS Math.round half-up is preserved on negative deltas', () {
      // Dart's .round() would give -0.3 here; JS Math.round gives -0.2.
      final cards = buildOverviewCards([weight], [
        const EntryLike(entryDate: '2026-07-01', entryTime: '08:00:00', answers: {'weight': '80'}),
        const EntryLike(entryDate: '2026-07-02', entryTime: '08:00:00', answers: {'weight': '79.75'}),
      ]);
      final tsMeta = (ts['negativeDelta'] as List)[0]['meta'];
      expect(cards.single.meta!.delta, tsMeta['delta']);
      expect(cards.single.meta!.deltaText, tsMeta['deltaText']);
    });
  });

  group('FIX #1: a blank answer is skipped, not plotted as zero', () {
    test('TS plotted a phantom 0 for the blank day', () {
      // Pin the old behaviour so this stays a deliberate divergence.
      final tsDay = (ts['dailySums'] as List)
          .firstWhere((d) => d['date'] == '2026-07-13');
      expect(tsDay['value'], 0, reason: 'TS aggregated blank weight as 0');
    });

    test('Dart omits the blank day entirely', () {
      final days = dailySums(weight, entries).map((d) => d.date).toList();
      expect(days, isNot(contains('2026-07-13')));
      expect(days, ['2026-07-10', '2026-07-11', '2026-07-12', '2026-07-14']);
    });

    test('weight series no longer drops to zero', () {
      final values = timeSeries(weight, entries).map((p) => p.value).toList();
      expect(values, isNot(contains(0)));
      expect(values, [80.5, 79.46, 79, 78.5]);
    });

    test('non-numeric text is still skipped, as in the TS', () {
      // 'abc' was already skipped by the TS; only blanks were mishandled.
      final days = dailySums(reps, entries).map((d) => d.date).toList();
      expect(days, isNot(contains('2026-07-13')));
      final tsDays = (ts['dailySumsReps'] as List).map((d) => d['date']).toList();
      expect(days, tsDays);
    });

    test('KPI delta is no longer measured against a phantom zero', () {
      final card = buildOverviewCards([weight], entries).single;
      // TS: value 78.5, delta +78.5 vs a 0 that never happened.
      final tsMeta = (ts['buildOverviewCards'] as List)[0]['meta'];
      expect(tsMeta['delta'], 78.5);
      expect(card.meta!.value, 78.5);
      expect(card.meta!.delta, -0.5); // 78.5 vs the real previous day, 79
      expect(card.meta!.deltaText, '-0.5 vs prev');
    });

    test('average ignores blanks instead of dragging toward zero', () {
      // TS averaged in the blank as 0 across 6 entries; Dart averages the 5 real ones.
      expect(ts['average'], lessThan(average(weight, entries)));
      expect(average(weight, entries), 63.5); // (80+0.5+79.456+79+78.5)/5, JS-rounded
    });

    test('rating average is not dragged down by an unanswered day', () {
      // TS: (4+2+5+1+0+3)/6 = 2.5, where that 0 is a day the client never rated.
      // Dart: (4+2+5+1+3)/5 = 3.
      final tsValue = (ts['buildOverviewCards'] as List)[1]['meta']['value'];
      expect(tsValue, 2.5);
      expect(buildOverviewCards([mood], entries).single.meta!.value, 3);
      expect(average(mood, entries), 3);
    });
  });

  group('FIX #2: dates are not shifted a day earlier', () {
    test('TS labelled 2026-07-10 as the previous day west of UTC', () {
      final offset = ts['meta']['tzOffsetMinutes'] as int;
      final tsFirstLabel = (ts['timeSeries'] as List).first['label'] as String;
      if (offset > 0) {
        expect(tsFirstLabel, '7/9', reason: 'TS is off by one behind UTC');
      } else {
        expect(tsFirstLabel, '7/10');
      }
    });

    test('Dart labels the actual entry date', () {
      expect(timeSeries(weight, entries).first.label, '7/10');
      expect(timeSeries(weight, entries).last.label, '7/14');
    });

    test('tooltip keeps the full ISO date and times', () {
      final first = timeSeries(weight, entries).first;
      expect(first.tooltip, '2026-07-10 at 08:30, 18:00');
    });
  });

  group('numericFieldStats', () {
    test('only numeric fields, with blanks excluded', () {
      final stats = numericFieldStats([weight, reps, mood], entries);
      expect(stats.map((s) => s.key), ['weight', 'reps']);

      final w = stats.first;
      expect(w.unit, 'kg');
      expect(w.count, 5); // blank excluded
      expect(w.min, 0.5);
      expect(w.max, 80);
      expect(w.latest, 78.5);
      expect(w.hasData, isTrue);
    });

    test('a field with no data reports zeros, not a crash', () {
      final stats = numericFieldStats([weight], const []);
      expect(stats.single.hasData, isFalse);
      expect(stats.single.count, 0);
      expect(stats.single.average, 0);
      expect(stats.single.min, 0);
    });
  });

  group('withinRange', () {
    test('range 0 returns everything untouched', () {
      expect(withinRange(entries, DateRange.all).length, entries.length);
    });

    test('filters to the trailing window inclusive of today', () {
      // A range of N covers today-(N-1) .. today, so today-N falls outside.
      final today = DateTime.now();
      String iso(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      EntryLike at(int daysAgo) => EntryLike(
            entryDate: iso(today.subtract(Duration(days: daysAgo))),
            answers: const {'weight': '1'},
          );

      final recent = [at(0), at(3), at(29), at(30)];

      expect(withinRange(recent, DateRange.week).length, 2); // today, -3
      expect(withinRange(recent, DateRange.month).length, 3); // + -29, but not -30
      expect(withinRange(recent, DateRange.quarter).length, 4);
    });

    test('includes an entry exactly on the cutoff day', () {
      final today = DateTime.now();
      String iso(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final onCutoff = [
        EntryLike(
          entryDate: iso(today.subtract(const Duration(days: 6))),
          answers: const {'weight': '1'},
        ),
      ];
      expect(withinRange(onCutoff, DateRange.week).length, 1);
    });

    test('ignores unparseable dates', () {
      final bad = [const EntryLike(entryDate: 'not-a-date', answers: {'weight': '1'})];
      expect(withinRange(bad, DateRange.week), isEmpty);
    });
  });
}

/// JSON numbers come back as int or double; normalise for comparison.
num _n(double v) => v == v.roundToDouble() ? v.toInt() : v;

void _expectPoints(List<DataPoint> actual, dynamic expected) {
  final exp = (expected as List)
      .map((p) => '${p['label']}=${p['value']}')
      .toList();
  expect(actual.map((p) => '${p.label}=${_n(p.value)}').toList(), exp);
}
