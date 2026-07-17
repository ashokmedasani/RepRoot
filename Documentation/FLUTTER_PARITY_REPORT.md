# Flutter Migration — Final Parity Report (2026-07-16)

The Android client is now a Flutter app in `mobile_flutter/`. All six phases of
[FLUTTER_MIGRATION_PLAN.md](FLUTTER_MIGRATION_PLAN.md) are complete. **The Ionic app in
`mobile/` is untouched and still builds** — it stays the fallback until this one has been
lived with for a while.

| | Ionic (`mobile/`) | Flutter (`mobile_flutter/`) |
|---|---|---|
| Stack | Angular 20 + Ionic 8 + Capacitor 7 | Flutter 3.44.6 / Dart 3.12.2 |
| Source | ~9,680 lines TS | ~20,400 lines Dart across 56 files |
| Tests | none | 51 passing (~940 lines) |
| Charts | Chart.js 4 | fl_chart |
| Font | Manrope (downloaded) | Roboto (Android system) |
| App id | `com.coachflow.app` | `com.coachflow.flutter` |
| Release APK | — | 56.7 MB (fat, all ABIs) |

Screens: **14 trainer**, **8 client**, 5 auth (role chooser, both logins, signup, profile
setup), 1 shared support incidents — 28, plus the two tab shells. Every route in
`mobile/src/app/app.routes.ts` has a Flutter counterpart at the same path, so deep links
stay portable. No placeholder screens remain.

The backend was not changed for the migration. The one backend change in this stretch —
the template-delete guard — was a product request applied to every client, not a
migration workaround.

## How this was verified

Against the **live Django backend with real seeded data** (trainer Nolan Brooks, 100
clients; client Ava Martinez, 63), on the Android emulator — not against mocks:

- Both roles sign in; trainer and client walkthroughs cover every screen.
- Bar, ring and line charts export as branded PNGs; the share sheet opens with the right
  caption. The exported files were pulled off the device and **looked at**, which is how
  two chart bugs were found.
- Dark mode: every screen, plus the dark branded-share composite.
- Release build: launches, signs in, refuses a plaintext base URL (below).
- `flutter analyze` clean; 51 tests green.

## The graph engine

`graph_engine.dart` is a 1:1 port of `graph-engine.ts` — the file that decides which
chart each template field gets. It is covered by **32 tests that diff the Dart output
against output from the real TypeScript**, compiled and run to produce
`test/fixtures/graph_engine_ts.json` (generator in `tools/tsfix/`). Not a
reimplementation checked by eye.

That diff surfaced **two live bugs in the TypeScript**, which the Dart port deliberately
does not reproduce (marked `FIX #1` / `FIX #2` in the source):

1. **`Number('')` is `0`, not `NaN`.** A client who skipped logging their weight got a
   body-weight chart that plunged to zero that day. Dart returns `NaN` and the point is
   dropped.
2. **Date-only strings parse as UTC midnight.** Read back as local time, every entry
   lands a day early anywhere west of UTC.

**Both bugs are still live in the web portal and the Ionic app.** They were left alone on
purpose — you asked for the write-up and a decision later. The fixes are small and the
tests already encode the correct behaviour. Full write-up, including how each was proved
by running the real TypeScript rather than reading it:
[CHANGELOG-graph-engine-bugs-2026-07-16.md](CHANGELOG-graph-engine-bugs-2026-07-16.md).

## Deliberate divergences from Ionic

Everything else matches the Ionic app screen for screen. These do not, on purpose:

- **Roboto, not Manrope**, and the whole scale is smaller (twice — once against Ionic,
  then again on request). Tap targets stay 44 px regardless of glyph size.
- **Branded share uses the real brand colors.** `branded-share.service.ts` hardcodes an
  off-brand palette (`#0b7de3` where the brand blue is `#2563EB`), so every graph an
  Ionic user shares carries a logo in the wrong blue.
- **A shared ring keeps its percentage.** In Ionic the number is an HTML overlay outside
  the `<canvas>`, so shared rings export as a bare donut. Capturing the widget subtree
  includes it.
- **Line charts don't clip their peaks.** fl_chart fits the y-axis exactly to the data, so
  the top point lands on the edge and the curve's spline overshoot is cut off — peaks
  rendered with flat tops. Chart.js rounds the scale outward, which is why Ionic never
  showed this. The range is padded 12%, floored at 0 for series that can't go negative.
- **Tokens are stored in `flutter_secure_storage`**, not `localStorage`.

## Security: the cleartext trap

`android:networkSecurityConfig` with `cleartextTrafficPermitted="false"` **does not
protect the app's API traffic**, though it reads exactly like it should. `dart:io` opens
its own sockets and never consults the platform HTTP stack. A release APK built with that
config signed straight into `http://10.0.2.2:8000` — full dashboard, live data, no
complaint. Every request carries the session token in an `Authorization` header, so on a
shared network that token was there for the taking.

The guard therefore lives in Dart, where the requests are: `main()` refuses a non-`https`
`API_BASE_URL` in release and fails at launch naming the fix. The manifest config is kept
because it does cover WebView and native plugin traffic; `debug`/`profile` replace it with
a permissive config so emulator and LAN dev keep working.

```
# release, plaintext -> refuses to start
flutter build apk --release --dart-define=API_BASE_URL=http://10.0.2.2:8000
# release against a LAN dev backend -> deliberate opt-out
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.4.68:8000 \
                            --dart-define=ALLOW_INSECURE_API=true
```

Both paths were run on the emulator and behaved as described.

## Known gaps

Nothing blocking, but honest:

- **Release signing uses the debug keystore** (`android/app/build.gradle.kts`). Fine for
  sideloading, must change before any store upload.
- **The APK is a 56.7 MB fat build.** `--split-per-abi` roughly thirds it; not done
  because nothing is being distributed yet.
- **iOS is unbuilt.** No Android-only APIs sit outside the platform folders, so the port
  should be mostly mechanical, but "should" is doing real work in that sentence — it has
  never been compiled for iOS.
- **A reminder's time can't be cleared.** `entry_time: null` / `time: null` can't be sent
  explicitly. Pre-existing across all three clients, not a migration regression.
- **No widget tests**, only unit tests. The UI was verified by driving the emulator.
- **The web portal's template-delete guard UI was never opened in a browser.** The backend
  guard is proven (a raw `DELETE` bypassing every UI returns HTTP 400); the web-side
  message is code-reviewed only.

## Build quickstart

```
# emulator (host backend at 10.0.2.2)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
# real phone on the LAN
flutter run --dart-define=API_BASE_URL=http://192.168.4.68:8000
```

The Flutter SDK lives at `C:\flutter` — it cannot sit under "Application Development",
because Flutter rejects a space in the SDK path. Gradle needs the Android Studio JBR
(system Java 25 fails with "Unsupported class file major version 69"); already pinned via
`flutter config --jdk-dir`. Emulator: `scripts/start-flutter-emulator.ps1`.
