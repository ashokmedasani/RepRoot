# Flutter Migration Plan — Phase 1 Audit & Roadmap (2026-07-15)

## Verdict

The existing mobile app is **NOT Flutter**. Migration applies.

| Aspect | Current |
|---|---|
| Framework | **Angular 20 + Ionic 8** (standalone components), **Capacitor 7** native shell |
| Language | TypeScript |
| Native target | Android (Gradle project in `mobile/android/`, JDK 21 required) |
| Charts | Chart.js 4 via a shared chart-card component |
| Fonts | Manrope variable font |
| Plugins | @capacitor/share, @capacitor/filesystem (branded chart sharing) |

## 1. Current project audit (`mobile/`, ~9,600 lines TS)

### Structure
```
mobile/src/app/
  core/config/api-config.ts        — API base URL resolution + localStorage session keys
  core/api/                        — 6 HTTP services (trainer-auth, client, forms-groups,
                                     templates, references, chat)
  pages/role-chooser/              — entry screen (Trainer | Client)
  pages/trainer/  (17 screens)     — login, signup, tabs shell, dashboard, clients,
                                     client-create, client-detail, client-template (analytics),
                                     manage hub, forms-groups, group-detail, templates,
                                     references, schedule, more, profile, settings
  pages/client/   (9 screens)      — login, tabs shell, dashboard, programs, progress,
                                     more, trainer profile, chat, settings
  pages/shared/support-incidents   — Help & Support (both roles)
  shared/                          — chart-card (Chart.js renderer + share button),
                                     branded-share.service (logo-watermarked PNG export),
                                     analytics/graph-engine (chart-type decision engine),
                                     mobile-form-field-editor, password-input
```

### Navigation
Angular Router, two bottom-tab shells:
- **Trainer:** Dashboard · Clients · Manage · More (Shop deferred by design)
- **Client:** Dashboard · Programs · Progress · More
Sub-pages stack inside tabs (client detail, template analytics, group detail, etc.).
Auth gates: role chooser skips to the right shell when a stored session exists; trainer
login/signup route incomplete profiles to a required profile-setup step.

### State management
None (deliberately simple): per-page component state + direct service calls.
Sessions in localStorage: `trainer-auth-token`, `client-auth-token`, `client-access`.

### API integration
Plain HttpClient against Django REST (`/api/accounts/...`). Headers:
`Authorization: Token <t>` (trainer) / `Authorization: ClientToken <t>` (client).
Base URL: derived from hostname in browser; `NATIVE_API_URL` constant for installed builds.
All request/response field names mirror the web frontend exactly.

### Authentication flow
Role chooser → login (trainer: identifier+password, OTP-verified signup; client:
trainer code+username+password with trainer directory search) → token stored →
tab shell. Client first login forces password change (token rotates; new token stored).
Trainer first login forces profile setup (name, trainer code, gender, birth, location).

### Reusable components worth carrying over (as specs/logic)
- **graph-engine.ts** — pure functions (no framework deps): decides line/bar/hbar/pie/
  ring/summary chart per template field, daily sums, ranges, numeric stats. **Ports 1:1 to Dart.**
- **branded-share.service.ts** — canvas compositing of chart + CoachFlow logo header →
  native share sheet. Port to Flutter using RepaintBoundary → image + share_plus.
- **chart-card.component.ts** — ChartSpec renderer contract (reimplement on fl_chart).
- **mobile-form-field-editor** — dynamic form field builder (label/type/required/options).
- Theme tokens in `variables.scss` (light+dark palettes, radii) — port to Material 3 ColorScheme.

### Documentation
`Documentation/` mirrors source files with per-file .md notes + dated changelogs;
`MOBILE_APP_DESIGN.md`, `MOBILE_VIEWING_GUIDE.md`, `mobile/README.md`. The same
convention will be extended with `Documentation/mobile_flutter/` during migration.

## 2. Prerequisites (must resolve before Phase 2)

- **Flutter SDK is not installed on this machine** (no `flutter`/`dart` on PATH).
  Phase 2 starts with installing Flutter stable (~1 GB download) and wiring it to the
  existing Android toolchain (Android Studio JBR JDK 21 already present and working).
- Android SDK already present (current app builds APKs); iOS build deferred but the
  architecture stays iOS-ready (no Android-only APIs outside platform folders).

## 3. Target Flutter architecture

```
mobile_flutter/
  lib/
    core/
      config/   env + api base url, secure session store
      api/      dio client + 6 API services (same endpoints, same field names)
      theme/    Material 3 design system (tokens below)
    shared/
      widgets/  AppCard, KpiTile, RowItem, StatusPill, SectionHeader, EmptyState,
                SkeletonLoader, AppSearchField, PasswordField, FormFieldEditor
      charts/   graph_engine.dart (1:1 port), ChartCard (fl_chart) + BrandedShare
    features/
      auth/       role chooser, trainer login/signup, client login, profile setup gate
      trainer/    dashboard, clients, client_detail, client_template, manage,
                  forms_groups, group_detail, templates, references, schedule,
                  more, profile, settings
      client/     dashboard, programs, progress, more, trainer_profile, chat, settings
      support/    support incidents (shared)
```

**Packages:** `go_router` (navigation, two StatefulShellRoutes for the tab shells),
`flutter_riverpod` (DI + per-feature state, no global store — matches current simplicity),
`dio` (HTTP + auth interceptors), `flutter_secure_storage` (tokens — an upgrade over
localStorage), `fl_chart` (charts), `share_plus` (native share), `image_picker` (photos),
`google_fonts` (Manrope). Material 3, Android first, iOS-ready.

## 4. UI/UX refinement layer (applied during migration, not after)

Per user feedback, current mobile sizing reads too large. The Flutter design system bakes
in a tighter scale from day one:

- **Icons:** 20–22 px in rows/buttons, 24 px nav bar (was ~26–32 px equivalents)
- **Type scale:** display 24 / title 17 / body 14.5 / label 12.5 / caption 11, Manrope
- **Spacing:** 4-pt grid; screen padding 16, card padding 14, list row height 56–64
- **Cards:** radius 12, elevation 0 with hairline border (calm/premium), consistent
- **Touch targets:** min 44×44 even where glyphs are smaller
- **Buttons:** one primary per screen, filled; secondary tonal/outlined; 44 px tall
- **Loading:** skeleton loaders on dashboards/lists; **Empty states:** icon + one-line
  guidance + primary action; **Errors:** friendly message + Retry
- Subtle 150–200 ms transitions only; no decorative motion

## 5. Migration roadmap (approval gate after every phase)

| Phase | Scope | Exit criteria |
|---|---|---|
| **2** | Install Flutter; scaffold `mobile_flutter/`; Android config (min SDK 23, cleartext dev config, app id `com.coachflow.app.flutter` during parallel run); theme + design system; dio client + all 6 API services; secure session store; go_router shells; role chooser + logins + signup + profile-setup gate | Sign in as trainer and client against the live Django backend; unit tests for API layer green |
| **3** | Shared widgets + chart engine: graph_engine Dart port (unit-tested against TS fixtures), ChartCard on fl_chart, branded share (logo header PNG → share sheet), form field editor, password field, skeleton/empty/error states | Widget gallery screen renders all components; chart parity spot-checked vs Chart.js output |
| **4** | Trainer portal: all 17 screens, per-screen parity check vs Ionic implementation | Full trainer walkthrough on device/emulator; parity checklist per screen; docs updated |
| **5** | Client portal: all 9 screens incl. forced password change and edit-request flows | Full client walkthrough; parity checklist; docs updated |
| **6** | Support incidents, remaining polish, dark mode QA, UI/UX review pass on every screen, release build (`flutter build apk`), final parity report | Feature-complete APK; documentation complete; Ionic app remains untouched as fallback |

**Rules throughout:** no backend changes unless a bug requires it; same endpoints,
field names, flows and screen names; the existing Ionic project (`mobile/`) is not
removed or modified; each phase ends with tests + docs + a stop for approval.

## 6. Risks / notes

- Chart visual parity: fl_chart ≠ Chart.js pixel-for-pixel; parity target is data
  correctness + equivalent readability, not identical rendering.
- The branded-share image must reproduce the CoachFlow header (logo mark + wordmark +
  chart title + footer) — implemented as a Flutter widget captured to PNG.
- Trainer profile photo/file uploads use multipart (dio FormData) — same endpoints.
- Dev-mode API base: Android emulator uses `10.0.2.2:8000`, device uses LAN IP —
  same convention as today via a build-time env.
