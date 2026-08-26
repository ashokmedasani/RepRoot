# Professional Side — Web vs Mobile Review

**Date:** 6 August 2026
**Scope:** Angular `frontend/src/app/pages/workspace/professional/` vs Flutter `mobile_flutter/lib/features/professional/`
**Method:** Route map, API-surface diff (146 Flutter API methods vs 9 Angular API services), shared business-logic comparison, static code-health scan of both codebases. Verified with `npx tsc --noEmit` (0 errors) and `flutter analyze` (0 issues).

---

## 1. Bugs fixed in this pass

### 1.1 UTC date bug corrupting streak & completion figures (web) — **fixed**

`professional-client-profile.component.ts` computed "today" with `new Date().toISOString().slice(0, 10)`. `toISOString()` converts to UTC **before** formatting, so west of UTC it returns *tomorrow's* date after roughly 19:00 local time.

Entry dates are stored as local calendar days, so for several hours every evening:

- the **streak** counter compared against a day that had no entries and reset to 0
- the **completion %** divided by the wrong `dayOfMonth` and used the wrong month prefix at month boundaries

The Flutter app has always used the local date (`_isoDate`), so the two platforms **silently disagreed** on the same client's numbers depending on the time of day. Mobile was correct; web was wrong.

Fixed by introducing a `toLocalIso()` helper and routing `todayIso()` plus the streak loop's cursor comparison through it.

**Files:** `professional-client-profile.component.ts` (lines ~1279, ~1364)

### 1.2 Same UTC bug in the client template page (web) — **fixed**

`professional-client-template.component.ts` had an identical `todayIso()`. Fixed the same way.

### 1.3 Schedule calendar grid shifted by one day (web) — **fixed**

`professional-schedule.component.ts` built every calendar cell's key with `cellDate.toISOString().slice(0, 10)`, where `cellDate` is constructed at **local midnight**. East of UTC, local midnight is the previous day in UTC — so the entire 42-cell grid was shifted one cell, mapping meeting counts, booked minutes and day-off shading onto the wrong dates.

Separately, `isToday` and the `min` attribute on the day-off date input used the same UTC expression, so the "today" highlight landed on tomorrow's cell during the evening west of UTC.

Fixed by adding a module-level `toLocalIso()` and using it for `todayIso`, `slotDate`, the grid cell keys, and the `isToday` comparison.

> Left alone deliberately: the two `getSlots(...)` calls at lines ~829 and ~907 parse `YYYY-MM-DD` as UTC midnight and format back through `toISOString()`. Both ends of that round-trip are UTC, so the result is correct.

### 1.4 Dead code and deprecated API (mobile) — **fixed earlier this session**

- Removed the unused `_initials` getter in `professional_dashboard_page.dart` (`flutter analyze` `unused_element` warning).
- Migrated the three `RadioListTile`s in `client_payments_panel.dart` from the deprecated per-tile `groupValue`/`onChanged` to a `RadioGroup<String>` ancestor (6 `deprecated_member_use` infos).

`flutter analyze` now reports **0 issues**, down from 7.

---

## 2. Real feature gaps — mobile is missing what the web has

These are functions a professional can perform on the website but **cannot** perform in the app. Ordered by my read of impact.

### 2.1 Grant / revoke client portal access — **missing entirely**

`grantPortalAccess` and `revokePortalAccess` exist in the web's forms-groups API and are wired into the client profile page (open dialog → set username/password → optionally email credentials). Neither the API method nor any UI exists in Flutter.

Consequence: a professional who creates a client manually on mobile has **no way to give that client a login**. They must switch to a desktop browser. This is the most user-visible gap found.

### 2.2 Editing a client's tracking entry — **API present, never called**

`templates_api.dart` defines `updateEntry(...)`, but no Flutter file calls it. The web's client-template page has a full edit flow (`startEntryEdit` / `saveEntryEdit` / `cancelEntryEdit`). Flutter's `professional_client_template_page.dart` can only **create** entries (`_saveEntry` → `createClientEntry`).

Consequence: a typo in a logged entry can't be corrected from the app.

### 2.3 Payment notifications feed on the dashboard — **API present, never called**

`getProfessionalPaymentUnread` and `markProfessionalPaymentNotificationsRead` are defined in `payments_api.dart` and never used. The web dashboard polls the first every 10s, renders a notification list, shows an unread count on the Payments tab pill, and deep-links each notification to the exact client/request via its `action_url`.

Flutter's dashboard polls chat unread only. Payment events are invisible until the professional navigates to Payments manually.

### 2.4 Shared references on a template assignment — **API present, never called**

`updateAssignmentReferences` is defined but unused. Web has `openShareDialog` / `saveSharedReferences` on the client-template page, letting a professional pick which resources the client sees for that assignment. No mobile equivalent.

### 2.5 Transaction ledger — missing

Web's payment-settings page calls `getTransactionLedger`; Flutter has no such API method and no ledger view. `previewPaymentMethod` is likewise absent (web previews a method before saving).

### 2.6 Smaller gaps

| Capability | Web | Mobile |
|---|---|---|
| Remove profile photo (`removeProfilePhoto`) | ✅ | ❌ no API, no UI |
| Clear all notifications (`clearNotifications`) | ✅ | ❌ |
| Plan downgrade assessment (`getDowngradeAssessment`) | ✅ dedicated call | ⚠️ fields parsed from another payload; no explicit check |
| Decline a group registration (`declineRegistrationSubmission`) | ✅ group-users page | ❌ |
| `checkEmail` (signup availability check) | ✅ | ❌ |
| Export a single client (`exportClient`) | ✅ | ✅ present |

---

## 3. Structural divergences — intentional or acceptable

Not bugs; recording them so they aren't "re-fixed" later.

- **Web routes that are dialogs on mobile.** Group create, lead-form create, tracking-template create/edit, and form-request detail are all standalone routes on web and bottom sheets / dialogs in Flutter. This is the right mobile pattern — not a gap.
- **Meeting request review lives in a different place.** Web offers accept/decline inline on the client profile (`reviewMeetingRequest`). Flutter has `reviewClientMeetingRequest` wired into `professional_schedule_page.dart` instead. Functionality is present, discoverability differs.
- **`professional-access`** is a public web landing route with no mobile counterpart, which is correct.
- **Public lead-capture endpoints** (`getPublicForm`, `submitPublicForm`, `getPublicGroupRegistration`, `submitPublicGroupRegistration`, `getPublicMeetingSlots`, `requestPublicMeeting`) are web-only by design — they serve unauthenticated prospects.
- **Joined date** sits only under "Show all details" on mobile, always visible in the web info grid. Confirmed intentional.
- **Poll intervals differ**: web polls chat unread at 5s everywhere; Flutter uses 8s for chat messages and 5s for unread counts. Harmless, but worth a deliberate decision rather than drift.

---

## 4. Code health

### Both codebases are in good shape

Checks that came back clean across both:

- No `TODO` / `FIXME` / `HACK` markers anywhere
- No `console.log` left in the Angular source; no `print()` in Dart
- No `: any` types in the professional Angular components
- No hardcoded credentials or API keys in either client
- No broken relative imports in Flutter (89 files checked)
- All brace/paren/bracket structures balanced (39,856 lines of Dart)
- Every `TextEditingController` is disposed; every `dispose()` calls `super.dispose()`
- No `ref.watch()` misuse inside `initState`
- No unguarded `BuildContext` use after `await` in a bare statement position
- **All timers are cleaned up on both platforms** — every `setInterval` has a matching `clearInterval` in `ngOnDestroy`, every Dart `Timer.periodic` has a matching `.cancel()` in `dispose()`. This is the most common leak in both frameworks and it's handled correctly throughout.

### Worth improving (not bugs)

**4.1 `_isoDate` is copy-pasted into 6 Flutter files**
`client_payments_page.dart`, `client_programs_page.dart`, `professional_client_create_page.dart`, `professional_client_detail_page.dart`, `professional_client_template_page.dart`, `widgets/client_payments_panel.dart`.

All six implementations are currently **identical**, so there's no live bug — but this is exactly the shape of the web bug fixed in §1: one date helper drifting from the others. `professional_format.dart` already exists as the shared formatting home; these belong there.

**4.2 Ten silent `catch (_) {}` blocks in Flutter**
In `client_change_password_page`, `client_more_page`, `client_settings_page` (×2), `professional_manage_page`, `professional_more_page`, `professional_payments_page`, `professional_settings_billing_page`, `professional_settings_plan_storage_page`, `professional_settings_recycle_bin_page`.

These are best-effort background loads where failing quietly is the right call. The gap is that the app has a working crash-reporting pipeline (`ErrorReportApi` → `error_logs` table) that these failures never reach, so a systematically failing endpoint would be invisible. Consider reporting at `warning` level while still swallowing the UI impact.

**4.3 Angular components subscribe without `takeUntilDestroyed`**
18 professional components subscribe to HTTP observables with no teardown. HTTP observables complete after one emission so this does not leak — but it does mean a late response can call `next` on a destroyed component. The six components that own timers already implement `ngOnDestroy` correctly.

**4.4 `deleteAccount` is dead on both platforms**
Defined in `professional-auth-api.service.ts` and `professional_auth_api.dart`; called from neither UI. Either wire up account deletion or drop the method — a live endpoint with no caller invites accidental use.

---

## 5. Suggested priority

1. **Grant/revoke portal access on mobile** (§2.1) — blocks a real workflow
2. **Entry editing on mobile** (§2.2) — API already exists, UI-only work
3. **Payment notifications on the mobile dashboard** (§2.3) — API already exists
4. Consolidate `_isoDate` into `professional_format.dart` (§4.1) — cheap, prevents a repeat of §1
5. Shared references + transaction ledger (§2.4, §2.5)
6. Route silent catches into the existing error reporter (§4.2)
