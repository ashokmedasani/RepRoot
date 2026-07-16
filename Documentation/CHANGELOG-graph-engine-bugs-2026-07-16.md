# Two chart bugs found in the existing apps (2026-07-16)

Found while porting `graph-engine.ts` to Dart for the Flutter migration. Both are
**present in the live web portal and the live Ionic mobile app**, and both were
confirmed empirically by compiling the real TypeScript with `tsc` and running it
under node — not by reading the code.

Both are **fixed in the Flutter port only**. The web and Ionic apps are
**unchanged**; fixing them there is a separate decision (see below).

Reproduction harness: `mobile_flutter/tools/tsfix/` (generates
`mobile_flutter/test/fixtures/graph_engine_ts.json` from the real source).

---

## Bug 1 — a blank answer is plotted as zero

`numericValue()` is:

```ts
function numericValue(raw: unknown): number {
  return Number(String(raw ?? '').trim());
}
```

In JavaScript **`Number('') === 0`**, not `NaN`. Every caller guards with
`!Number.isNaN(raw)`, so a blank answer passes the guard and aggregates as a
real zero.

**Effect.** On a day a client submits an entry but leaves a numeric field blank,
that field's chart shows a data point of **0**. Real output from the actual TS,
for a body-weight series:

```
7/9=80.5   7/10=79.46   7/11=79   7/12=0   7/13=78.5
```

A body-weight chart that drops to zero and back. It also corrupts the KPI card:
the "latest vs previous" delta compares against the phantom zero, producing
`"+78.5 vs prev"`. Rating averages are dragged down the same way — a mood average
reads **2.5** instead of **3**, because an unanswered day counts as a zero rating.

Note the inconsistency: non-numeric text (`'abc'`) *is* correctly skipped, because
`Number('abc')` really is `NaN`. Only blanks were mishandled.

**Severity:** this misrepresents client data in a way a trainer would read as a
real measurement. It gets worse the more optional fields a template has.

**Fix in Flutter:** blank/missing answers return NaN and are skipped, exactly as
non-numeric text already was.

---

## Bug 2 — every chart label is one day early (west of UTC)

`shortDate()` is:

```ts
function shortDate(iso: string): string {
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? iso : `${date.getMonth() + 1}/${date.getDate()}`;
}
```

Per the ECMAScript spec, a **date-only** string like `'2026-07-15'` parses as
**UTC midnight**. `getMonth()` / `getDate()` then read it back in **local** time.
Anywhere west of UTC that lands on the previous day.

Confirmed on this machine (UTC-4):

```
$ node -e "console.log(new Date('2026-07-15').getDate())"
14
```

**Effect.** Every x-axis label on every chart is one day early for any user
behind UTC — the whole of the Americas. An entry logged on the 15th is labelled
`7/14`. `withinRange()` has the same root cause (`new Date(entry.entry_date)`
compared against a *local* midnight cutoff), so range filtering is shifted by the
UTC offset too, and boundary entries can fall in or out of a "last 7 days" window
incorrectly.

**Severity:** cosmetic-but-misleading. The shape of the data is right; the dates
are wrong. Trainers correlating a chart against a client's diary would see
everything shifted a day.

**Fix in Flutter:** Dart's `DateTime.parse` treats date-only strings as local
midnight, which is what the data means.

---

## Status of the existing apps

Not fixed. Both files still carry the bugs:

- `frontend/src/app/shared/analytics/graph-engine.ts`
- `mobile/src/app/shared/analytics/graph-engine.ts`

The two copies have **identical** `numericValue` and `shortDate`; they differ only
in chart-type selection (mobile added the bar/line and pie/hbar switches plus
`meta.subtitle`).

If they are fixed later, it is roughly a two-line change per file:

```ts
function numericValue(raw: unknown): number {
  const text = String(raw ?? '').trim();
  return text === '' ? NaN : Number(text);
}

function shortDate(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  if (!y || !m || !d) return iso;
  return `${m}/${d}`;
}
```

`withinRange` needs the same date-parsing treatment to be consistent.

**Consequence of not fixing them:** the Flutter charts and the web/Ionic charts
will legitimately disagree — Flutter correct, the others not. Anyone comparing
the two during Phase 4/5 parity checks should expect this and should not "fix"
Flutter to match. The parity target set in `FLUTTER_MIGRATION_PLAN.md` is data
correctness, not identical rendering.

Deciding whether to fix web + Ionic was deferred deliberately (2026-07-16).
