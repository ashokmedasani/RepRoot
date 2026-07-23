# Flutter Migration — Phase 2: Foundation (2026-07-16)

Scaffold, toolchain, design system, API layer, and the full auth flow.
The Ionic app in `mobile/` is untouched and remains the fallback.

## Toolchain (installed this phase)

| Piece | Value |
|---|---|
| Flutter | 3.44.6 stable, Dart 3.12.2 |
| SDK location | `C:\flutter` — **not** under `Application Development`: Flutter forbids spaces in the SDK path |
| PATH | `C:\flutter\bin` added to the **user** PATH |
| JDK | pinned via `flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"` (JDK 21) |
| Android SDK | existing install reused; `android-sdk-license` already accepted |

**Why the JDK pin matters:** system Java is 25, which Gradle rejects with
"Unsupported class file major version 69". The pin is stored in Flutter's own
config, so `flutter build` works without setting `JAVA_HOME` per shell — unlike
the Ionic app's `gradlew.bat` builds, which still need it exported.

`flutter doctor` reports two non-blocking issues, both expected:
- **cmdline-tools missing** — only needed for `flutter doctor --android-licenses`
  and for creating emulators. APK builds work without it (Gradle accepted the
  CMake license itself during the first build).
- **Visual Studio incomplete** — only affects Windows *desktop* builds. Irrelevant
  to Android/iOS.

## Project

```
mobile_flutter/
  lib/
    main.dart                     app entry; warms the session cache pre-first-frame
    app/router.dart               go_router; paths mirror mobile/src/app/app.routes.ts
    core/
      config/env.dart             API base URL (build-time --dart-define)
      session/session_store.dart  secure token storage + in-memory cache
      api/
        api_client.dart           dio + auth/error interceptors, ApiException
        trainer_auth_api.dart     trainer auth/profile/account
        client_api.dart           client auth slice
        models/                   trainer_models.dart, client_models.dart
      theme/
        app_tokens.dart           colors, spacing, radii, sizes, ThemeExtension
        app_theme.dart            Material 3 light + dark
    shared/widgets/               password_field.dart, auth_brand.dart
    features/
      auth/                       role chooser, trainer login, signup, profile setup, client login
      trainer/trainer_tabs_shell.dart
      client/client_tabs_shell.dart
      placeholder_page.dart       stand-in for not-yet-migrated screens (has sign-out)
  test/
    core/api_client_test.dart     19 hermetic tests
    live/live_auth_test.dart      6 live-backend tests (opt-in)
```

**Android config:** app id `com.coachflow.flutter` (distinct from the Ionic app's
`com.coachflow.app`, so both install side by side during the migration — switch at
release). Label "CoachFlow", `usesCleartextTraffic=true` and INTERNET permission
for LAN dev, minSdk from Flutter's default (24).

**Packages:** go_router, flutter_riverpod, dio, flutter_secure_storage, fl_chart,
share_plus, image_picker, google_fonts, path_provider, intl.

## API base URL

No webview hostname to derive from, so it is a build-time constant
(`Env.apiBaseUrl`, default `http://192.168.4.68:8000` — the PC's LAN IP, matching
`NATIVE_API_URL` in the Ionic app):

```
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000       # emulator
flutter run --dart-define=API_BASE_URL=http://192.168.4.68:8000   # phone on LAN
```

## Design system — the tightened scale

Per feedback that the Ionic app reads too large, the Flutter design system is a
step down from day one, while staying above the 44 px touch-target floor.

| Token | Flutter | Ionic equivalent |
|---|---|---|
| Primary button height | **46** | ~52 (`size="large"`) |
| Secondary button height | 38 | ~44 |
| Icon (rows/buttons) | 20–22 | ~26–32 |
| Icon (nav bar) | 24 | ~28 |
| Nav bar height | 62 | ~68 |
| Card radius | 12 | 12–20 |
| Screen / card padding | 16 / 14 | 16 / 16 |

Type scale (Manrope): display 24 · title 17 · body 14.5 · label 12.5 · caption 11.

Colors are a 1:1 port of `mobile/src/theme/variables.scss` — both light and dark
palettes, same hex values. Brand colors were **not** changed. Tokens Material has
no slot for (`surfaceSoft`, `muted`, `border`, `primarySoft`, `accent`, `success`,
shadows) live in an `AppTokens` ThemeExtension, read via `context.tokens`.

## Auth flow (parity notes)

- **Role chooser** → trainer or client login; a stored session skips straight to
  the matching tab shell (session cache is warmed in `main()` so there is no flash).
- **Trainer login** → on success, `getProfileStatus()` decides dashboard vs.
  profile setup. If that status call itself fails, the user proceeds to the
  dashboard rather than being stranded on the login screen.
- **Trainer signup** → username check → email OTP → verify → create account →
  **always** profile setup. Validation rules copied exactly: username 5–10 chars
  `[A-Za-z0-9.-]`, password ≥8 with one special character.
- **Profile setup gate** — required first-login step (name, trainer code, gender,
  birth month/year, country, state). This exists because a trainer who reaches the
  dashboard without a trainer code has clients who can never sign in.
- **Client login** → trainer code + username + password, with the trainer directory
  search/picker. Username is lowercased before submit, as in the Ionic app.

**Two auth schemes on one API root:** `Authorization: Token <t>` (trainer) vs.
`ClientToken <t>` (client). A dio interceptor picks the token from
`Options.extra`, so a request can never be sent with the wrong role's token —
covered by a test, since both sessions can exist on one device.

**Session storage** is an upgrade over the Ionic app: Android Keystore via
`flutter_secure_storage` instead of localStorage, same logical keys
(`trainer-auth-token`, `client-auth-token`, `client-access`). Tokens are cached in
memory so the interceptor stays synchronous.

## Verification

- `flutter analyze` — **no issues**.
- `flutter test` — **19 passed** (auth interceptor, error mapping, Env, model
  parsing, session store).
- `flutter test test/live --dart-define=LIVE=true --dart-define=API_BASE_URL=http://localhost:8000`
  — **6 passed** against the live Django backend:
  trainer sign-in + profile + status, bad-password error, trainer directory,
  client sign-in, wrong-trainer-code error.
- `flutter build apk --debug` — **succeeds** (183 MB debug APK).
- **Driven on an Android 35 emulator against the live backend** — see below.

### Emulator

Created this phase, since none existed: AVD **`coachflow_pixel`** (Pixel 7,
Android 35, `google_apis;x86_64`). This required installing Android
**cmdline-tools** (`sdkmanager` 12.0) into the SDK, which also clears the
`flutter doctor` cmdline-tools warning.

```
flutter emulators --launch coachflow_pixel
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### On-device walkthrough (2026-07-16, all passed)

| Step | Result |
|---|---|
| Role chooser renders | Brand mark, palette, tighter buttons all correct |
| Trainer sign-in (`nolan.performance@example.com`) | Reached trainer tab shell |
| Profile-setup gate | Correctly routed to dashboard (profile already complete) |
| Trainer sign-out | Returned to role chooser, session cleared |
| Trainer directory picker | Loaded live trainers; picking one filled the code |
| Client sign-in (`nolan` / `ava_martinez`) | Reached client tab shell |
| Password show/hide toggle | Works |
| Dark mode (`adb shell cmd uimode night yes`) | Correct dark palette |

Not yet exercised on device: trainer signup + OTP, and the profile-setup form
submitting (the seeded trainer's profile is already complete). Both are covered
by the code paths above but warrant a pass when a fresh account is next created.

**Emulator quirk, not an app bug:** the Android 35 image pops a "Try out your
stylus" tutorial that swallows `adb shell input text`. Disable it before scripted
input: `adb shell settings put secure stylus_handwriting_enabled 0`. Also note
`adb shell input text` mangles `!` — wrap the whole command instead:
`adb shell "input text 'TrainerScale!2026'"`.

## Deferred / notes

- Only the trainer-auth and client-auth API slices are ported. The remaining four
  services (forms-groups, templates, references, chat) land with the screens that
  use them in Phases 4–5.
- Tab screens are placeholders; real screens are Phase 4 (trainer) / Phase 5 (client).
- The client forced-password-change gate belongs in the client tab shell (Phase 5),
  matching where the Ionic app enforces it.
- `usesCleartextTraffic=true` is for LAN dev over HTTP. Restrict or remove before
  a production release over HTTPS.
- iOS is not scaffolded yet (Android-first by request). No Android-only APIs are
  used outside the platform folder, so `flutter create --platforms=ios .` will add
  it when wanted.
