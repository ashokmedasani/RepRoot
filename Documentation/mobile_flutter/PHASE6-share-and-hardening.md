# Phase 6 — branded share, chart fixes, release hardening

Covers the last slice of the Flutter migration. Companion to
[PHASE2-foundation.md](PHASE2-foundation.md); the overall result is in
[../FLUTTER_PARITY_REPORT.md](../FLUTTER_PARITY_REPORT.md).

## `lib/shared/charts/branded_share.dart`

**What it does.** Exports a chart as a PNG carrying the CoachFlow Studio header (logo mark,
wordmark, tagline, chart title, context line) and a footer, then opens the Android share
sheet.

**Why it exists.** The Flutter counterpart of `mobile/src/app/shared/branded-share.service.ts`.
Ionic rasterises a Chart.js `<canvas>` with the Canvas 2D API. Here the chart is a widget
subtree, so it is captured through a `RepaintBoundary` and composited with `dart:ui`.

**Data flow.** `ChartCard` owns a `GlobalKey` on a `RepaintBoundary` wrapping *only* the
chart body (not the title row — the branded header reprints the title itself).
`BrandedShare.shareChart` finds that boundary, `toImage(pixelRatio: 3)`, composites onto a
`PictureRecorder` canvas, encodes PNG, writes to the temp dir, and hands the file to
`SharePlus.instance.share`.

**Key decisions.**

- **Colors come from `AppColors`.** The TS service hardcodes an off-brand palette
  (`#0b7de3` vs the real `#2563EB`), so every graph an Ionic user shares carries a logo in
  the wrong blue. Do not "restore parity" here — that would reintroduce the bug.
- **Layout is equivalent, not pixel-identical**, the same stance the chart renderer takes.
  The header is two stacked lines rather than Ionic's cramped single line.
- **Exported at 3x** so it survives a messaging app's recompression.
- **The dumbbell glyph uses the 24-unit grid** from the web/Ionic brand mark, so all three
  apps draw one logo.
- `intl` is imported `show DateFormat` — it also exports a `TextDirection` that shadows
  `dart:ui`'s and breaks `TextPainter`.

**Assumption.** The boundary has painted. If it hasn't, `shareChart` returns `false` and
`ChartCard` shows a snackbar rather than throwing.

## `lib/shared/charts/chart_card.dart`

Now a `StatefulWidget`. The share button needs no wiring from callers — the card captures
itself, so the five call sites that already passed `shareContext` work unchanged. Hidden on
`summary` specs, as in Ionic: nothing to export from a single number.

Two fl_chart defects fixed here, both found by looking at exported PNGs:

- **`_paddedBounds`** — fl_chart fits the y-axis exactly to the data, so the top point
  lands on the plot edge and the curved line's spline overshoots and clips; peaks rendered
  with flat tops. Chart.js rounds its scale outward to nice bounds, which is why Ionic
  never showed this. Pads 12%, floored at 0 for series that can't go negative.
- **Bottom-axis max label dropped** — fl_chart labels the axis max *on top of* the interval
  sequence (the same trap `_leftTitle` already worked around). The last point sits hard on
  the right edge, so its label was half outside the card — it exported as `7/` — and
  overprinted the tick a day or two behind it. A tap still gives the exact date.

## Release hardening

**`lib/core/config/env.dart` — `assertSecureBaseUrl()`, called from `main()`.**

`android:networkSecurityConfig` with `cleartextTrafficPermitted="false"` does **not**
protect this app's API traffic. `dart:io` opens its own sockets and never consults the
platform HTTP stack — a release APK with that config signed straight into
`http://10.0.2.2:8000` on the emulator. Session tokens ride in an `Authorization` header,
so they were going out in the clear.

The guard is therefore in Dart. Release + non-`https` base URL throws at launch (a build
mistake should be impossible to miss) unless `--dart-define=ALLOW_INSECURE_API=true`, the
opt-out for pointing a release build at a LAN dev backend.

**Manifests.** `main/` now points at an HTTPS-only `network_security_config.xml`; `debug/`
and `profile/` `tools:replace` it with a permissive one so emulator and LAN dev work. The
manifest config is kept because it does cover WebView and native plugin traffic — it just
can't cover ours. This retires the blanket `usesCleartextTraffic="true"`.

`android:enableOnBackInvokedCallback="true"` enables Android 13+ predictive back. Safe
because nothing in the app uses `WillPopScope` or `PopScope`, so there is no back
interception to break.

## Future improvements

- Split the APK per ABI (56.7 MB fat build) and add a real release keystore before any
  store upload.
- `BrandedShare` is Android-verified only; the iOS share sheet wants
  `sharePositionOrigin` on iPad.
- Widget tests for `ChartCard` — the chart fixes above were caught by eye, and a golden
  test would have caught them cheaper.
