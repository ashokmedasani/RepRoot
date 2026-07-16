import 'dart:math' as math;

import 'analytics_types.dart';

/// Graph engine — the ONLY place chart-type selection lives.
/// 1:1 port of mobile/src/app/shared/analytics/graph-engine.ts.
///
/// Given a template field, the client's entries, and a date range, it decides
/// which chart best represents that field and returns a ChartSpec. Consumers
/// render ChartSpecs via ChartCard, so chart logic is never duplicated.
///
/// Two deliberate deviations from the TypeScript original are marked DEVIATION
/// below; everything else matches its behaviour exactly, including JS rounding
/// semantics and the `Number('') === 0` quirk.

String fieldKey(FieldLike field) => field.key.isNotEmpty ? field.key : field.label;

String extractUnit(String label) {
  final match = RegExp(r'\(([^)]+)\)').firstMatch(label);
  return match != null ? match.group(1)!.trim() : '';
}

/// Mirrors JS `Math.round`, which rounds half **up** (toward +Infinity).
/// Dart's `.round()` rounds half *away from zero*, so they disagree on negative
/// halves: JS gives -2 for -2.5, Dart gives -3. That matters for KPI deltas,
/// which can be negative.
double _jsRound(double value) => (value + 0.5).floorToDouble();

/// FIX #1 (differs from the TS on purpose).
///
/// The TS uses `Number(String(raw ?? '').trim())`, and `Number('')` is **0**,
/// not NaN. Callers branch on NaN, so a blank answer was aggregated as zero:
/// a client who skipped logging their weight got a body-weight chart that
/// **plunged to 0** that day, and a KPI delta measured against that phantom
/// zero. Non-numeric text ('abc') was correctly skipped, so the old behaviour
/// was not even self-consistent.
///
/// Here a blank/missing answer is NaN, so it is skipped like any other
/// unanswered field. Verified against the TS in test/shared/graph_engine_test.
double _numericValue(Object? raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return double.nan;
  return double.tryParse(text) ?? double.nan;
}

/// FIX #2 (differs from the TS on purpose).
///
/// The TS uses `new Date(iso)`, which parses a date-only string as **UTC
/// midnight**, then reads it back with local getters. Anywhere west of UTC that
/// reports the previous day: on a UTC-4 machine `new Date('2026-07-15')`
/// renders as "7/14", so every chart label was one day early and range
/// filtering was shifted. Dart parses date-only strings as local midnight,
/// which is what the data means.
DateTime? _parseDate(String iso) {
  try {
    return DateTime.parse(iso);
  } catch (_) {
    return null;
  }
}

/// Chronological ascending by date then time.
List<EntryLike> sortByTime(List<EntryLike> entries) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    final left = '${a.entryDate} ${a.entryTime.isEmpty ? '00:00' : a.entryTime}';
    final right = '${b.entryDate} ${b.entryTime.isEmpty ? '00:00' : b.entryTime}';
    return left.compareTo(right);
  });
  return sorted;
}

List<EntryLike> withinRange(List<EntryLike> entries, int range) {
  if (range == 0) return entries;

  final now = DateTime.now();
  final cutoff = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: range - 1));

  return entries.where((entry) {
    final date = _parseDate(entry.entryDate);
    return date != null && !date.isBefore(cutoff);
  }).toList();
}

String _shortDate(String iso) {
  final date = _parseDate(iso);
  return date == null ? iso : '${date.month}/${date.day}';
}

// ----- per-field aggregations -----

class DailySum {
  const DailySum({required this.date, required this.value, required this.times});

  final String date;
  final double value;
  final List<String> times;
}

/// Sums a numeric field's values per day (multiple entries on the same day are
/// added together), returned oldest-first. Only numbers are aggregated this way.
List<DailySum> dailySums(FieldLike field, List<EntryLike> entries) {
  final key = fieldKey(field);
  final sums = <String, double>{};
  final times = <String, List<String>>{};

  for (final entry in entries) {
    final raw = _numericValue(entry.answers[key]);

    if (!raw.isNaN) {
      sums[entry.entryDate] = (sums[entry.entryDate] ?? 0) + raw;
      final time = entry.entryTime.length >= 5
          ? entry.entryTime.substring(0, 5)
          : entry.entryTime;
      if (time.isNotEmpty) {
        final list = times.putIfAbsent(entry.entryDate, () => <String>[]);
        // A Set in the TS — keep insertion order, drop duplicates.
        if (!list.contains(time)) list.add(time);
      }
    }
  }

  final result = sums.entries
      .map((e) => DailySum(
            date: e.key,
            value: _jsRound(e.value * 100) / 100,
            times: times[e.key] ?? const [],
          ))
      .toList();
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}

List<DataPoint> timeSeries(FieldLike field, List<EntryLike> entries) {
  return dailySums(field, entries)
      .map((point) => DataPoint(
            label: _shortDate(point.date),
            value: point.value,
            tooltip:
                '${point.date}${point.times.isNotEmpty ? ' at ${point.times.join(', ')}' : ''}',
          ))
      .toList();
}

List<DataPoint> frequency(FieldLike field, List<EntryLike> entries) {
  final key = fieldKey(field);
  final counts = <String, double>{};

  for (final entry in entries) {
    final value = (entry.answers[key] ?? '').trim();
    if (value.isNotEmpty) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
  }

  final result =
      counts.entries.map((e) => DataPoint(label: e.key, value: e.value)).toList();
  result.sort((a, b) => b.value.compareTo(a.value));
  return result;
}

List<DataPoint> ratingDistribution(FieldLike field, List<EntryLike> entries) {
  final key = fieldKey(field);
  final scale = _ratingScale(field);
  final counts = List<double>.filled(scale, 0);

  for (final entry in entries) {
    final raw = _numericValue(entry.answers[key]);
    if (raw.isNaN) continue;
    final value = _jsRound(raw).toInt();
    if (value >= 1 && value <= scale) {
      counts[value - 1] += 1;
    }
  }

  return [
    for (var i = 0; i < counts.length; i++)
      DataPoint(label: '${i + 1}', value: counts[i]),
  ];
}

/// `Math.min(10, Math.max(2, field.scale || 5))` — note `|| 5` also replaces 0.
int _ratingScale(FieldLike field) {
  final raw = (field.scale == null || field.scale == 0) ? 5 : field.scale!;
  return math.min(10, math.max(2, raw));
}

double average(FieldLike field, List<EntryLike> entries) {
  final key = fieldKey(field);
  final values = entries
      .map((entry) => _numericValue(entry.answers[key]))
      .where((value) => !value.isNaN)
      .toList();

  if (values.isEmpty) return 0;

  final sum = values.fold<double>(0, (a, b) => a + b);
  return _jsRound((sum / values.length) * 10) / 10;
}

double completionPercent(FieldLike field, List<EntryLike> entries) {
  final key = fieldKey(field);
  final answered = entries
      .map((entry) => (entry.answers[key] ?? '').trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toList();

  if (answered.isEmpty) return 0;

  final yes = answered
      .where((value) => value == 'yes' || value == 'true' || value == '1')
      .length;
  return _jsRound((yes / answered.length) * 100);
}

class _LatestNumeric {
  const _LatestNumeric(this.value, this.previous);
  final double value;
  final double? previous;
}

/// Numbers are summed per day, so the KPI compares the latest day's total
/// against the previous day's total.
_LatestNumeric _latestNumeric(FieldLike field, List<EntryLike> entries) {
  final days = dailySums(field, entries);
  return _LatestNumeric(
    days.isNotEmpty ? days.last.value : 0,
    days.length > 1 ? days[days.length - 2].value : null,
  );
}

// ----- selection -----

ChartSpec? decideChartForField(
  FieldLike field,
  List<EntryLike> entries,
  int range,
) {
  final inRange = withinRange(entries, range);
  final unit = extractUnit(field.label);

  switch (field.fieldType) {
    case 'number':
      final data = timeSeries(field, inRange);
      if (data.isEmpty) return null;
      // A handful of daily values reads more clearly as rounded columns on a
      // phone. Longer series become a smooth area trend.
      return ChartSpec(
        kind: data.length <= 8 ? ChartKind.bar : ChartKind.line,
        title: field.label,
        unit: unit,
        data: data,
        meta: ChartMeta(
          subtitle: data.length <= 8 ? 'Daily values' : 'Trend over time',
        ),
      );

    case 'rating':
      final data = ratingDistribution(field, inRange);
      if (!data.any((bar) => bar.value > 0)) return null;
      return ChartSpec(
        kind: ChartKind.hbar,
        title: field.label,
        data: data,
        meta: ChartMeta(
          average: average(field, inRange),
          subtitle: 'Rating distribution',
        ),
      );

    case 'yes_no':
      final percent = completionPercent(field, inRange);
      return ChartSpec(
        kind: ChartKind.ring,
        title: field.label,
        data: const [],
        meta: ChartMeta(percent: percent, subtitle: 'Completion'),
      );

    case 'dropdown':
      final data = frequency(field, inRange);
      if (data.isEmpty) return null;
      return ChartSpec(
        kind: data.length <= 4 ? ChartKind.pie : ChartKind.hbar,
        title: field.label,
        data: data,
        meta: const ChartMeta(subtitle: 'Response breakdown'),
      );

    case 'short_text':
      final data = frequency(field, inRange);
      if (data.isEmpty) return null;
      return ChartSpec(
        kind: ChartKind.hbar,
        title: field.label,
        data: data,
        meta: const ChartMeta(subtitle: 'Most common responses'),
      );

    default:
      // long_text and any unknown/legacy types get no chart.
      return null;
  }
}

class NumericFieldStat {
  const NumericFieldStat({
    required this.key,
    required this.label,
    required this.unit,
    required this.count,
    required this.average,
    required this.latest,
    required this.min,
    required this.max,
    required this.hasData,
  });

  final String key;
  final String label;
  final String unit;
  final int count;
  final double average;
  final double latest;
  final double min;
  final double max;
  final bool hasData;
}

/// Per numeric field: count / average / latest / min / max from submitted data.
List<NumericFieldStat> numericFieldStats(
  List<FieldLike> fields,
  List<EntryLike> entries,
) {
  final ordered = sortByTime(entries);

  return fields.where((field) => field.fieldType == 'number').map((field) {
    final key = fieldKey(field);
    final values = entries
        .map((entry) => _numericValue(entry.answers[key]))
        .where((value) => !value.isNaN)
        .toList();
    final orderedValues = ordered
        .map((entry) => _numericValue(entry.answers[key]))
        .where((value) => !value.isNaN)
        .toList();
    final count = values.length;
    double round(double value) => _jsRound(value * 10) / 10;

    return NumericFieldStat(
      key: key,
      label: field.label,
      unit: extractUnit(field.label),
      count: count,
      average: count > 0
          ? round(values.fold<double>(0, (a, b) => a + b) / count)
          : 0,
      latest: orderedValues.isNotEmpty ? orderedValues.last : 0,
      min: count > 0 ? values.reduce(math.min) : 0,
      max: count > 0 ? values.reduce(math.max) : 0,
      hasData: count > 0,
    );
  }).toList();
}

/// Decides every chart for a template's fields, dropping fields with no chart.
List<ChartSpec> buildFieldCharts(
  List<FieldLike> fields,
  List<EntryLike> entries,
  int range,
) {
  return fields
      .map((field) => decideChartForField(field, entries, range))
      .whereType<ChartSpec>()
      .toList();
}

/// KPI summary cards for the overview strip (numeric latest, rating avg, yes/no %).
List<ChartSpec> buildOverviewCards(
  List<FieldLike> fields,
  List<EntryLike> entries,
) {
  final cards = <ChartSpec>[];

  for (final field in fields) {
    final unit = extractUnit(field.label);

    if (field.fieldType == 'number') {
      final latest = _latestNumeric(field, entries);
      final delta = latest.previous == null
          ? null
          : _jsRound((latest.value - latest.previous!) * 10) / 10;
      cards.add(
        ChartSpec(
          kind: ChartKind.summary,
          title: field.label,
          unit: unit,
          data: const [],
          meta: ChartMeta(
            value: latest.value,
            unit: unit,
            delta: delta,
            deltaText: delta == null
                ? ''
                : '${delta > 0 ? '+' : ''}${_trimNum(delta)} vs prev',
          ),
        ),
      );
    } else if (field.fieldType == 'rating') {
      cards.add(
        ChartSpec(
          kind: ChartKind.summary,
          title: field.label,
          data: const [],
          meta: ChartMeta(
            value: average(field, entries),
            subtitle: 'avg of ${_ratingScale(field)}',
          ),
        ),
      );
    } else if (field.fieldType == 'yes_no') {
      final percent = completionPercent(field, entries);
      cards.add(
        ChartSpec(
          kind: ChartKind.summary,
          title: field.label,
          data: const [],
          meta: ChartMeta(
            valueText: '${_trimNum(percent)}%',
            subtitle: 'completed',
          ),
        ),
      );
    }
  }

  return cards;
}

/// JS prints 3.0 as "3" and 3.5 as "3.5"; Dart's toString keeps the ".0".
String _trimNum(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}
