# RepRoot Mobile — Design Blueprint (Android + iOS)

> **Superseded.** This was the design blueprint for the original Ionic/Capacitor
> mobile app, which has since been replaced by a Flutter rewrite and removed from
> the repo entirely. Kept as historical record of the original screen/flow design;
> see `FLUTTER_MIGRATION_PLAN.md` and `FLUTTER_PARITY_REPORT.md` for what came after.

**Date:** 2026-07-10
**Stack:** Ionic 8 + Capacitor 7 on Angular 20 (standalone components) — one codebase, native Android + iOS builds.
**Backend:** the existing Django REST API at `/api/accounts/` is used **unchanged**. Professional auth = `Token <key>`, client auth = `ClientToken <key>` — identical to the web app.
**App model:** ONE app in both stores, role-based entry. Professional and Client experiences are fully separated — separate logins, separate navigation shells, separate screens. No mixed pages.

---

## 1. Why Ionic + Capacitor

- The web frontend is Angular 20; Ionic Angular reuses the exact same language, DI, router, and HttpClient patterns.
- The six API services in `frontend/src/app/core/api/` are plain HttpClient classes — they were copied into the mobile app nearly verbatim (`mobile/src/app/core/api/`).
- Capacitor wraps the built web bundle in a native shell; `npx cap add android` / `npx cap add ios` produce real store-ready projects.
- Mobile progress charts are rendered from the same measurable template entries as the web application; the Android build is the only native target for this release.

## 2. Project layout

```
mobile/
  package.json            Angular 20 + @ionic/angular 8 + @capacitor 7
  angular.json            @angular/build application builder
  ionic.config.json       Ionic project marker
  capacitor.config.ts     appId com.reproot.app, webDir www
  src/
    main.ts               bootstrap + provideIonicAngular + provideHttpClient
    index.html
    global.scss           app-wide styles (uses tokens)
    theme/variables.scss  --app-* tokens mapped to --ion-color-*
    environments/         apiBaseUrl per environment
    app/
      app.component.ts    <ion-app><ion-router-outlet/>
      app.routes.ts       role chooser + professional shell + client shell
      core/
        config/api-config.ts      resolves apiBaseUrl (emulator/device/prod)
        api/                      six services copied from the web app
      pages/
        role-chooser/
        professional/   login, tabs shell, dashboard, clients, client-detail, + stubs
        client/    login, tabs shell, templates, + stubs
        shared/    stub-page component
```

### API base URL rules (important on device)
| Where the app runs | `apiBaseUrl` |
| --- | --- |
| Browser dev (`npm start`) | `http://127.0.0.1:8000` |
| Android emulator | `http://10.0.2.2:8000` |
| Real device on your Wi‑Fi | `http://<your-PC-LAN-IP>:8000` (add to Django `ALLOWED_HOSTS` + CORS) |
| Production | your Render URL |

Set in `src/environments/environment.ts`. Sessions use localStorage (persists in the Capacitor webview); migrating to `@capacitor/preferences` is a Phase 4 hardening task.

---

## 3. Entry flow

```
Splash (Ionic default)
  └─ Role Chooser  ──────────────  "I'm a Professional"  →  Professional Login → Professional Shell
        │                          "I'm a Client"   →  Client Login  → Client Shell
        └─ stored token found → skip straight to that role's shell
```

---

## 4. PROFESSIONAL experience — 5 bottom tabs

Every screen is separate; tabs hold stacks (push/pop navigation).

### Tab 1 — Dashboard
| Screen | Purpose | API |
| --- | --- | --- |
| **Dashboard** | KPI cards (Groups, Clients, Pending, Templates); Upcoming Schedules expandable list (Open Client / Mark Complete); Activity expandable | `GET professional/forms-groups/` · `GET professional/reminders/upcoming/` · `PUT professional/reminders/<id>/` |

### Tab 2 — Clients
| Screen | Purpose | API |
| --- | --- | --- |
| **Client List** | All clients grouped by group, search | `GET professional/forms-groups/` · `GET .../groups/<id>/clients/` |
| **Client Workspace** | Segmented: Info (compact rows + Edit Profile + Password) / Notes / Scheduler / Templates / Additional Info; pending change-request approve/reject | `GET .../clients/<id>/` · notes, reminders, additional-info, change-request endpoints |
| **Client Template Detail** | Segmented: Overview (numeric stats + charts) · References (accordion) · Data Entries (filter/export/edit≤72h) · Progress (professional timeline) | assignments, entries, progress endpoints |
| **Client Chat** | Full-screen chat with this client | `GET/POST professional/clients/<id>/chat/` |

### Tab 3 — Forms & Groups
| Screen | Purpose | API |
| --- | --- | --- |
| **Forms & Groups Overview** | Lead form card + link share (native share sheet), request tabs (Pending/Approved/Deleted), groups list | `GET professional/forms-groups/` |
| **Lead Form Builder** | Suggested-field chips + custom fields | `POST .../lead-form/` |
| **Form Request Detail** | Full submission + assign-to-group + create client access (auto-fill) | `POST .../pending/<id>/create-client-access/` |
| **Group Create / Group Detail / Client Form Builder** | Same flows as web, one screen each | groups + registration-form endpoints |

### Tab 4 — Templates
| Screen | Purpose | API |
| --- | --- | --- |
| **Template Library** | My templates (max 5) + adopt standard | `GET professional/templates/` · standard endpoints |
| **Template Builder** | Fields N/8, dropdown/rating editors | `POST/PUT professional/templates/` |

### Tab 5 — More
| Screen | Purpose | API |
| --- | --- | --- |
| **Profile** | Read-only portfolio, per-section Public/Private, Preview as Client | `GET professional/profile/` · `PUT professional/profile/visibility/` |
| **References** | Category accordion → inline reference expand | references endpoints |
| **Settings** | Account (professional code, delete) / My Account (edit profile form) / Change Password | account endpoints |
| **Logout** | clear token → role chooser | `POST professional/logout/` |

---

## 5. CLIENT experience — 4 bottom tabs

### Tab 1 — My Templates
| Screen | Purpose | API |
| --- | --- | --- |
| **Templates Home** | Assigned templates as cards (template chips when >1) | `GET client/templates/` |
| **Template Overview** | Numeric stats + charts | `GET client/entries/` (+ graph engine) |
| **Template References** | Accordion (YouTube inline, PDF open, text, image) | data from templates payload |
| **Add Entry** | Date+time + dynamic fields (number/dropdown/rating/yes-no/text) | `POST client/entries/` |
| **Previous Entries** | Per-day grouped history; edit ≤72h | `GET client/entries/` · `PUT client/entries/<id>/` |
| **Progress** | Shared professional progress notes | `GET client/progress/` |

### Tab 2 — Professional
Public professional profile: photo, headline, and only sections the professional marked Public. `GET client/me/` (`professional_profile`).

### Tab 3 — Chat
Full-screen professional chat. `GET/POST client/chat/`.

### Tab 4 — My Details
Account rows, registration details (read-only + "Request an edit" → professional approval), shared Additional Information, photo upload, change password. `client/me/`, `client/detail-change-request/`, `client/photo/`, `client/change-password/`.

> The **public lead form** stays web-only — it is shared by URL with people who don't have the app.

---

## 6. Theming

`src/theme/variables.scss` ports the web tokens (`--app-bg`, `--app-surface`, `--app-text`, `--app-primary`, …) and maps them to Ionic (`--ion-color-primary`, `--ion-background-color`, `--ion-text-color`, …). Dark mode: `@media (prefers-color-scheme: dark)` mirrors the web `[data-theme='dark']` palette. All four web themes can be added later by toggling a class on `<html>`.

## 7. Phased build plan

| Phase | Scope | Status |
| --- | --- | --- |
| **1. Scaffold** | Project, theme, API services, role chooser, both logins, professional Dashboard + Clients (live data), client Templates + Add Entry (live data), stubs for every other screen | ✅ this delivery |
| **Professional screens** | Forms & Groups flows, client workspace details, template detail, references, profile, settings, and support requests | Android release scope |
| **3. Client screens** | Professional profile tab, chat, My Details incl. edit requests | you / next sessions |
| **4. Native polish** | `@capacitor/preferences` token storage, push notifications for reminders/chat, camera plugin for photos, app icons/splash, store builds | later |

## 8. Running it

```bash
cd mobile
npm install
npm start                 # browser dev at http://localhost:4400
npm run build             # production web bundle → www/

# native (requires Android Studio / Xcode)
npx cap add android
npx cap add ios
npx cap sync
npx cap open android      # build/run from Android Studio
```

Set your backend URL first in `src/environments/environment.ts`.
