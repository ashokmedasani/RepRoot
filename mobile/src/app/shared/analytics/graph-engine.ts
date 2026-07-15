import { ChartSpec, DataPoint, DateRange, EntryLike, FieldLike } from './analytics.types';

/**
 * Graph engine — the ONLY place chart-type selection lives.
 *
 * Given a template field, the client's entries, and a date range, it decides
 * which chart best represents that field and returns a ChartSpec. Consumers
 * (Template View, client portal, future reports) render ChartSpecs via the
 * shared chart-renderer, so chart logic is never duplicated.
 */

export function fieldKey(field: FieldLike): string {
  return field.key || field.label;
}

export function extractUnit(label: string): string {
  const match = label.match(/\(([^)]+)\)/);
  return match ? match[1].trim() : '';
}

function numericValue(raw: unknown): number {
  return Number(String(raw ?? '').trim());
}

/** Chronological ascending by date then time. */
export function sortByTime(entries: EntryLike[]): EntryLike[] {
  return [...entries].sort((a, b) => {
    const left = `${a.entry_date} ${a.entry_time || '00:00'}`;
    const right = `${b.entry_date} ${b.entry_time || '00:00'}`;
    return left.localeCompare(right);
  });
}

export function withinRange(entries: EntryLike[], range: DateRange): EntryLike[] {
  if (!range) {
    return entries;
  }

  const cutoff = new Date();
  cutoff.setHours(0, 0, 0, 0);
  cutoff.setDate(cutoff.getDate() - (range - 1));

  return entries.filter((entry) => {
    const date = new Date(entry.entry_date);
    return !Number.isNaN(date.getTime()) && date >= cutoff;
  });
}

function shortDate(iso: string): string {
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? iso : `${date.getMonth() + 1}/${date.getDate()}`;
}

// ----- per-field aggregations -----

/**
 * Sums a numeric field's values per day (multiple entries on the same day are
 * added together), returned oldest-first. Only numbers are aggregated this way.
 */
export function dailySums(field: FieldLike, entries: EntryLike[]): { date: string; value: number; times: string[] }[] {
  const key = fieldKey(field);
  const sums = new Map<string, number>();
  const times = new Map<string, Set<string>>();

  for (const entry of entries) {
    const raw = numericValue(entry.answers?.[key]);

    if (!Number.isNaN(raw)) {
      sums.set(entry.entry_date, (sums.get(entry.entry_date) || 0) + raw);
      const time = String(entry.entry_time || '').slice(0, 5);
      if (time) {
        const dateTimes = times.get(entry.entry_date) || new Set<string>();
        dateTimes.add(time);
        times.set(entry.entry_date, dateTimes);
      }
    }
  }

  return [...sums.entries()]
    .map(([date, value]) => ({ date, value: Math.round(value * 100) / 100, times: [...(times.get(date) || [])] }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

export function timeSeries(field: FieldLike, entries: EntryLike[]): DataPoint[] {
  return dailySums(field, entries).map((point) => ({
    label: shortDate(point.date),
    value: point.value,
    tooltip: `${point.date}${point.times.length ? ` at ${point.times.join(', ')}` : ''}`
  }));
}

export function frequency(field: FieldLike, entries: EntryLike[]): DataPoint[] {
  const key = fieldKey(field);
  const counts = new Map<string, number>();

  for (const entry of entries) {
    const value = String(entry.answers?.[key] ?? '').trim();

    if (value) {
      counts.set(value, (counts.get(value) || 0) + 1);
    }
  }

  return [...counts.entries()]
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value);
}

export function ratingDistribution(field: FieldLike, entries: EntryLike[]): DataPoint[] {
  const key = fieldKey(field);
  const scale = Math.min(10, Math.max(2, field.scale || 5));
  const counts = new Array(scale).fill(0);

  for (const entry of entries) {
    const value = Math.round(numericValue(entry.answers?.[key]));

    if (value >= 1 && value <= scale) {
      counts[value - 1] += 1;
    }
  }

  return counts.map((value, index) => ({ label: String(index + 1), value }));
}

export function average(field: FieldLike, entries: EntryLike[]): number {
  const key = fieldKey(field);
  const values = entries.map((entry) => numericValue(entry.answers?.[key])).filter((value) => !Number.isNaN(value));

  if (!values.length) {
    return 0;
  }

  return Math.round((values.reduce((sum, value) => sum + value, 0) / values.length) * 10) / 10;
}

export function completionPercent(field: FieldLike, entries: EntryLike[]): number {
  const key = fieldKey(field);
  const answered = entries.map((entry) => String(entry.answers?.[key] ?? '').trim().toLowerCase()).filter(Boolean);

  if (!answered.length) {
    return 0;
  }

  const yes = answered.filter((value) => value === 'yes' || value === 'true' || value === '1').length;
  return Math.round((yes / answered.length) * 100);
}

function latestNumeric(field: FieldLike, entries: EntryLike[]): { value: number; previous: number | null } {
  // Numbers are summed per day, so the KPI compares the latest day's total
  // against the previous day's total.
  const days = dailySums(field, entries);

  return {
    value: days.length ? days[days.length - 1].value : 0,
    previous: days.length > 1 ? days[days.length - 2].value : null
  };
}

// ----- selection -----

export function decideChartForField(field: FieldLike, entries: EntryLike[], range: DateRange): ChartSpec | null {
  const inRange = withinRange(entries, range);
  const unit = extractUnit(field.label);

  switch (field.field_type) {
    case 'number': {
      const data = timeSeries(field, inRange);
      if (!data.length) {
        return null;
      }

      // A handful of daily values reads more clearly as rounded columns on a
      // phone. Longer series become a smooth area trend.
      return {
        kind: data.length <= 8 ? 'bar' : 'line',
        title: field.label,
        unit,
        data,
        meta: { subtitle: data.length <= 8 ? 'Daily values' : 'Trend over time' }
      };
    }
    case 'rating': {
      const data = ratingDistribution(field, inRange);
      return data.some((bar) => bar.value > 0)
        ? { kind: 'hbar', title: field.label, data, meta: { average: average(field, inRange), subtitle: 'Rating distribution' } }
        : null;
    }
    case 'yes_no': {
      const percent = completionPercent(field, inRange);
      return { kind: 'ring', title: field.label, data: [], meta: { percent, subtitle: 'Completion' } };
    }
    case 'dropdown': {
      const data = frequency(field, inRange);

      if (!data.length) {
        return null;
      }

      return {
        kind: data.length <= 4 ? 'pie' : 'hbar',
        title: field.label,
        data,
        meta: { subtitle: 'Response breakdown' }
      };
    }
    case 'short_text': {
      const data = frequency(field, inRange);
      return data.length
        ? { kind: 'hbar', title: field.label, data, meta: { subtitle: 'Most common responses' } }
        : null;
    }
    default:
      // long_text and any unknown/legacy types get no chart.
      return null;
  }
}

export interface NumericFieldStat {
  key: string;
  label: string;
  unit: string;
  count: number;
  average: number;
  latest: number;
  min: number;
  max: number;
  hasData: boolean;
}

/** Per numeric field: count / average / latest / min / max from submitted data. */
export function numericFieldStats(fields: FieldLike[], entries: EntryLike[]): NumericFieldStat[] {
  const ordered = sortByTime(entries);

  return fields
    .filter((field) => field.field_type === 'number')
    .map((field) => {
      const key = fieldKey(field);
      const values = entries
        .map((entry) => numericValue(entry.answers?.[key]))
        .filter((value) => !Number.isNaN(value));
      const orderedValues = ordered
        .map((entry) => numericValue(entry.answers?.[key]))
        .filter((value) => !Number.isNaN(value));
      const count = values.length;
      const round = (value: number): number => Math.round(value * 10) / 10;

      return {
        key,
        label: field.label,
        unit: extractUnit(field.label),
        count,
        average: count ? round(values.reduce((sum, value) => sum + value, 0) / count) : 0,
        latest: orderedValues.length ? orderedValues[orderedValues.length - 1] : 0,
        min: count ? Math.min(...values) : 0,
        max: count ? Math.max(...values) : 0,
        hasData: count > 0
      };
    });
}

/** Decides every chart for a template's fields, dropping fields with no chart. */
export function buildFieldCharts(fields: FieldLike[], entries: EntryLike[], range: DateRange): ChartSpec[] {
  return fields
    .map((field) => decideChartForField(field, entries, range))
    .filter((spec): spec is ChartSpec => spec !== null);
}

/** KPI summary cards for the overview strip (numeric latest, rating avg, yes/no %). */
export function buildOverviewCards(fields: FieldLike[], entries: EntryLike[]): ChartSpec[] {
  const cards: ChartSpec[] = [];

  for (const field of fields) {
    const unit = extractUnit(field.label);

    if (field.field_type === 'number') {
      const { value, previous } = latestNumeric(field, entries);
      const delta = previous === null ? undefined : Math.round((value - previous) * 10) / 10;
      cards.push({
        kind: 'summary',
        title: field.label,
        unit,
        data: [],
        meta: { value, unit, delta, deltaText: delta === undefined ? '' : `${delta > 0 ? '+' : ''}${delta} vs prev` }
      });
    } else if (field.field_type === 'rating') {
      cards.push({
        kind: 'summary',
        title: field.label,
        data: [],
        meta: { value: average(field, entries), subtitle: `avg of ${Math.min(10, Math.max(2, field.scale || 5))}` }
      });
    } else if (field.field_type === 'yes_no') {
      const percent = completionPercent(field, entries);
      cards.push({
        kind: 'summary',
        title: field.label,
        data: [],
        meta: { valueText: `${percent}%`, subtitle: 'completed' }
      });
    }
  }

  return cards;
}
