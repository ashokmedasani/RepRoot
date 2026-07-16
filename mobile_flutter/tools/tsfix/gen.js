// Generates fixtures from the REAL graph-engine.ts so the Dart port can be
// diffed against it rather than against assumptions.
const e = require('./out/graph-engine.js');

const fields = {
  weight: { key: 'weight', label: 'Body weight (kg)', field_type: 'number' },
  reps: { key: 'reps', label: 'Reps', field_type: 'number' },
  mood: { key: 'mood', label: 'Mood', field_type: 'rating', scale: 5 },
  moodBig: { key: 'moodBig', label: 'Mood big', field_type: 'rating', scale: 99 },
  moodZero: { key: 'moodZero', label: 'Mood zero', field_type: 'rating', scale: 0 },
  done: { key: 'done', label: 'Workout done', field_type: 'yes_no' },
  meal: { key: 'meal', label: 'Meal type', field_type: 'dropdown' },
  meal6: { key: 'meal6', label: 'Meal six', field_type: 'dropdown' },
  note: { key: 'note', label: 'Note', field_type: 'short_text' },
  essay: { key: 'essay', label: 'Essay', field_type: 'long_text' },
  noKey: { label: 'No key field', field_type: 'number' },
};

const entries = [
  { entry_date: '2026-07-10', entry_time: '08:30:00', answers: { weight: '80', mood: '4', done: 'yes', meal: 'Breakfast', note: 'good', reps: '10' } },
  { entry_date: '2026-07-10', entry_time: '18:00:00', answers: { weight: '0.5', mood: '2', done: 'no', meal: 'Dinner', note: 'good', reps: '5' } },
  { entry_date: '2026-07-11', entry_time: '09:00:00', answers: { weight: '79.456', mood: '5', done: 'yes', meal: 'Breakfast', note: 'ok', reps: '8' } },
  { entry_date: '2026-07-12', entry_time: '07:15:00', answers: { weight: '79', mood: '1', done: 'true', meal: 'Lunch', note: 'bad', reps: '12' } },
  // blank + non-numeric answers exercise the Number('')===0 quirk and NaN skip
  { entry_date: '2026-07-13', entry_time: '', answers: { weight: '', mood: '', done: '', meal: '', note: '', reps: 'abc' } },
  { entry_date: '2026-07-14', entry_time: '10:00:00', answers: { weight: '78.5', mood: '3', done: '1', meal: 'Snack', note: 'ok', reps: '9' } },
];

// Long series (>8 points) to trip the bar->line switch
const longEntries = [];
for (let d = 1; d <= 10; d++) {
  const day = String(d).padStart(2, '0');
  longEntries.push({ entry_date: `2026-06-${day}`, entry_time: '08:00:00', answers: { weight: String(70 + d) } });
}

// 6 distinct dropdown values to trip the pie->hbar switch
const dropdownEntries = ['A', 'B', 'C', 'D', 'E', 'F'].map((v, i) => ({
  entry_date: `2026-06-0${i + 1}`,
  entry_time: '08:00:00',
  answers: { meal6: v },
}));

const ALL = 0;

const out = {
  meta: {
    tzOffsetMinutes: new Date().getTimezoneOffset(),
    note: 'generated from mobile/src/app/shared/analytics/graph-engine.ts',
  },
  fieldKey: {
    withKey: e.fieldKey(fields.weight),
    withoutKey: e.fieldKey(fields.noKey),
  },
  extractUnit: {
    withUnit: e.extractUnit('Body weight (kg)'),
    withoutUnit: e.extractUnit('Reps'),
    empty: e.extractUnit(''),
    nested: e.extractUnit('Volume (kg) total'),
  },
  dailySums: e.dailySums(fields.weight, entries),
  dailySumsReps: e.dailySums(fields.reps, entries),
  timeSeries: e.timeSeries(fields.weight, entries),
  frequency: e.frequency(fields.meal, entries),
  frequencyNote: e.frequency(fields.note, entries),
  ratingDistribution: e.ratingDistribution(fields.mood, entries),
  ratingDistributionClampHigh: e.ratingDistribution(fields.moodBig, entries),
  ratingDistributionScaleZero: e.ratingDistribution(fields.moodZero, entries),
  average: e.average(fields.weight, entries),
  averageMood: e.average(fields.mood, entries),
  completionPercent: e.completionPercent(fields.done, entries),
  numericFieldStats: e.numericFieldStats([fields.weight, fields.reps, fields.mood], entries),
  decide: {
    numberShort: e.decideChartForField(fields.weight, entries, ALL),
    numberLong: e.decideChartForField(fields.weight, longEntries, ALL),
    rating: e.decideChartForField(fields.mood, entries, ALL),
    yesNo: e.decideChartForField(fields.done, entries, ALL),
    dropdownSmall: e.decideChartForField(fields.meal, entries, ALL),
    dropdownBig: e.decideChartForField(fields.meal6, dropdownEntries, ALL),
    shortText: e.decideChartForField(fields.note, entries, ALL),
    longText: e.decideChartForField(fields.essay, entries, ALL),
    numberEmpty: e.decideChartForField(fields.weight, [], ALL),
  },
  buildFieldCharts: e.buildFieldCharts(
    [fields.weight, fields.mood, fields.done, fields.meal, fields.essay],
    entries,
    ALL
  ).map((s) => ({ kind: s.kind, title: s.title })),
  buildOverviewCards: e.buildOverviewCards([fields.weight, fields.mood, fields.done], entries),
  // negative delta exercises JS Math.round half-up vs Dart round-half-away
  negativeDelta: e.buildOverviewCards([fields.weight], [
    { entry_date: '2026-07-01', entry_time: '08:00:00', answers: { weight: '80' } },
    { entry_date: '2026-07-02', entry_time: '08:00:00', answers: { weight: '79.75' } },
  ]),
  sortByTime: e.sortByTime(entries).map((x) => `${x.entry_date} ${x.entry_time}`),
};

console.log(JSON.stringify(out, null, 2));
