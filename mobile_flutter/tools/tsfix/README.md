# TS fixture generator

Generates `test/fixtures/graph_engine_ts.json` from the **real**
`mobile/src/app/shared/analytics/graph-engine.ts`, so the Dart port in
`lib/shared/charts/graph_engine.dart` is verified against the TypeScript's
actual behaviour rather than against assumptions about it.

The graph engine has no Angular dependencies, so it compiles and runs standalone
under node.

## Regenerate

```bash
# from the repo root
SCRATCH=/tmp/tsfix && mkdir -p "$SCRATCH"
cp mobile/src/app/shared/analytics/graph-engine.ts \
   mobile/src/app/shared/analytics/analytics.types.ts "$SCRATCH/"
cp mobile_flutter/tools/tsfix/gen.js "$SCRATCH/"

cd mobile
node node_modules/typescript/bin/tsc --module commonjs --target es2020 \
  --outDir "$SCRATCH/out" "$SCRATCH/graph-engine.ts" "$SCRATCH/analytics.types.ts"

cd "$SCRATCH" && node gen.js \
  > "<repo>/mobile_flutter/test/fixtures/graph_engine_ts.json"
```

Then run `flutter test test/shared/graph_engine_test.dart`.

## Note on the two deliberate differences

The fixtures pin the TypeScript's behaviour **including two bugs** the Dart port
fixes on purpose (see FIX #1 / FIX #2 in `graph_engine.dart`, and
`Documentation/CHANGELOG-graph-engine-bugs-2026-07-16.md`):

1. A blank answer aggregates as `0` in the TS, plotting a phantom drop to zero.
2. Date-only strings parse as UTC, so labels are a day early west of UTC.

The test asserts the corrected Dart values *and* pins the old TS values, so the
divergence stays deliberate and visible. `meta.tzOffsetMinutes` in the fixture
records the generating machine's offset — bug #2 only manifests when it is > 0.
Regenerating on a UTC or east-of-UTC machine will change those TS values.
