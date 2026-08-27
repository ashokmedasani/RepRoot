# Backend TODO — from the professional parity review

**Branch:** `feature/professional-parity-fixes`
**Date:** 6 August 2026

## Summary: no backend changes were required

Every gap fixed in this pass was **client-side only**. All the endpoints the mobile app was missing already exist and are already in production use — the website calls them today. Mobile simply had no Dart method and/or no UI for them.

Nothing in `backend/` was edited on this branch by me.

---

## Endpoints now called by mobile for the first time

These were already live and exercised by the web client. Mobile now calls them too, so they will see **new traffic from a new client**. No schema, serializer, or view changes needed — but they're worth watching after release, since mobile is a new caller.

| Endpoint | Method | Previously called by | Now also called by |
|---|---|---|---|
| `/professional/forms-groups/clients/<id>/grant-access/` | POST | Web client profile | Mobile client detail → Actions |
| `/professional/forms-groups/clients/<id>/revoke-access/` | POST | Web client profile | Mobile client detail → Actions |
| `/professional/entries/<id>/` | PUT | Web client template | Mobile client template (edit entry) |
| `/professional/payments/notifications/` | GET + POST | Web dashboard | Mobile dashboard (10s poll + mark read) |
| `/professional/forms-groups/clients/<id>/assignments/<id>/` | PUT | Web share dialog | Mobile template → Shared resources |
| `/professional/notifications/` | DELETE | Web page shell | Mobile notifications → Clear all |
| `/professional/profile/photo/` | DELETE | Web profile form | Mobile profile → Remove photo |
| `/professional/forms-groups/groups/<id>/registration-submissions/<id>/decline/` | POST | Web group users | Mobile group detail → Decline |

**Load note:** the payment-notifications poll runs every 10 seconds per active professional dashboard, matching the web's existing interval. Mobile roughly doubles the poll volume per professional who uses both. It is only started once payment tracking is confirmed enabled for the account, so accounts without payments generate no extra traffic.

---

## Genuine backend work, if you want full parity

These are the only items that would need server-side changes. All are optional — none block anything currently shipping.

### 1. `POST /professional/payments/notifications/` — confirm the `mark_all` contract

The web sends `{ request_id }` to clear one request, or `{ mark_all: true }` to clear everything. Mobile now sends the identical payloads.

Worth a quick read of the view to confirm `mark_all` is honoured as an explicit flag, because the web's own code has a latent quirk:

```ts
requestId ? { request_id: requestId } : { mark_all: markAll || true }
```

`markAll || true` is **always** `true`, so the `markAll` parameter is dead — the web can never send `mark_all: false`. Harmless today (the only non-request call site does want mark-all), but if the backend ever treats a falsy `mark_all` as meaningful, the web can't express it. Either simplify the web call or leave a note in the view. **This is a frontend wart, not a backend bug** — listed here only because it affects the endpoint's contract.

### 2. `deleteAccount` — endpoint with no caller on either platform

`professional-auth-api.service.ts` and `professional_auth_api.dart` both define it; neither web nor mobile ever calls it. Either:

- wire up an account-deletion flow (needs a UI decision + probably a confirmation/grace-period policy), or
- remove the client methods and, if the view is likewise unreferenced, consider whether the endpoint should stay exposed.

A live destructive endpoint with no caller is worth an explicit decision rather than drift.

### 3. Client-side payment unread (`getClientPaymentUnread`)

Defined in the Dart API, unused on mobile. The web uses it in three client-portal components. Out of scope for this professional-only review — flagging so it isn't mistaken for dead code later.

### 4. Transaction ledger + payment-method preview

`getTransactionLedger` and `previewPaymentMethod` exist on the backend and are used by the web's payment-settings page. Mobile has neither Dart method nor UI. Not added in this pass because both need real screen design, not just wiring — the ledger is a dense table and the preview is a live-rendering step in the method form.

**No backend change needed when you do add them** — the endpoints are ready.

---

## Pre-existing uncommitted backend changes on this branch

Worth flagging since this is a production codebase. When I created the branch, `backend/` already had two uncommitted modified files that were **not** made by me:

- `backend/accounts/serializers.py` — 8 added lines exposing `lead_form` and `lead_form_title` on the lead-submission serializer (additive; the web interface ignores the extra fields, mobile uses them for per-form filtering)
- `backend/accounts/migrations/0039_alter_paymentrequest_status.py` — **line-ending changes only**, no functional diff

Also note the working tree has widespread CRLF/LF churn: 102 files show as modified, but only 54 have real content changes (`git diff --stat -w`). Consider a `.gitattributes` with `* text=auto` to stop this recurring — it makes every future diff and code review noisier than it needs to be.

---

# Addendum — items raised during the mobile UI/UX passes

**Date:** 7 August 2026
**Still true:** nothing in `backend/` has been edited by me. Everything below
needs a backend change and is therefore **not done**.

---

## A. Public app-config endpoint (blocks Google sign-in on mobile)

**Status:** open. Requested by the user; not implemented pending approval.

Mobile currently gets the Google OAuth client ID from a build flag
(`--dart-define=GOOGLE_SERVER_CLIENT_ID`, see `mobile_flutter/dart_defines.example.json`).
That is fragile: forget the flag and the Google button silently hides itself,
which is exactly what happened during testing.

The web does not have this problem because it reads
`window.APP_CONFIG.googleClientId`, injected into the page at deploy time.

Mobile cannot read `backend/.env` — it is a separate artifact running in a
browser/device, and `.env` also holds `SECRET_KEY`, the database URL, and
Stripe keys, none of which may ever reach a client.

**Proposed:** a small unauthenticated endpoint, e.g.

    GET /api/accounts/public/app-config/
    -> { "google_client_id": "...", "support_email": "..." }

Both values are already public (the client ID is embedded in every web page
that renders the Google button). Mobile fetches this at startup and drops the
build flag entirely, so web and mobile read one source — the stated rule that
web and mobile share data and settings.

Roughly 15 lines: one `APIView` reading `settings.GOOGLE_OAUTH_CLIENT_ID` and
`settings.SUPPORT_EMAIL`, plus a route. **Must not** echo anything else from
settings.

---

## B. Bulk "unassign template from all clients"

**Status:** open. Investigated on request; deliberately not implemented.

`TrackingTemplate` cannot be deleted while assigned (`views.py` ~3325). The
only way to unassign today is one at a time:

    DELETE /professional/forms-groups/clients/<client_id>/assignments/<assignment_id>/

Two problems for a client-side loop:

1. `TrackingTemplateSerializer` exposes only `assigned_count` — not the
   assignment IDs or which clients hold them. Mobile would have to walk every
   client and filter.
2. It would be N requests with no transaction. A partial failure leaves the
   template half-unassigned with no way to report which half.

**Data safety is fine** — `TrackingEntry.template` is `SET_NULL` with a
denormalised `template_name`, so past entries survive. The backend already
says "Past entries are kept."

**Proposed:** mirror the pattern that already exists for resources
(`views.py` ~3173) — a single POST that filters `TemplateAssignment` server-side
and deletes in one transaction, returning the affected count.

---

## C. Change-password re-authentication — CLOSED BY PRODUCT DECISION

**Status:** decided 7 August 2026. No backend change wanted. Recorded here so
the reasoning is not lost and nobody "fixes" it by accident.

`ProfessionalPasswordChangeSerializer` declares only `password` /
`confirm_password`. It has **never** had a `current_password` field, and its
own comment says re-confirmation was judged unnecessary friction.

Mobile was collecting "Current password" and POSTing `current_password`, which
DRF silently discarded as an undeclared field. The box looked like a check and
was not one. **That field has now been removed from mobile** so the UI matches
what actually happens.

The user's reasoning for keeping it this way:

- the request is already authenticated by token, and
- Google-authenticated professionals have no password to re-enter, so
  requiring one would lock them out of their own password settings.

**Residual risk, accepted:** a stolen or borrowed session token can be used to
set a new password without knowing the old one. `ProfessionalPasswordChangeView`
deletes all tokens afterwards, so the legitimate owner is signed out and will
notice — the attack is not silent, but it is not prevented either.

If this is ever revisited, the usual pattern is conditional re-auth —
require the current password only for accounts that have a usable one
(`user.has_usable_password()`), and fall back to a fresh-session or OTP check
for OAuth accounts. That satisfies both concerns without blocking Google users.

---

## D. Template `accent` — data written by older mobile builds

**Status:** fixed client-side; no backend action required. Noted for awareness.

`TrackingTemplate.accent` is a **named** value — `green` / `blue` / `orange` /
`purple` (model default `green`; all seed commands use names; the web matches
on those names to pick a border colour).

Older mobile builds wrote `#rrggbb` hex instead. Effects, both live until this
fix:

- templates created on mobile matched none of the web's four classes and
  rendered with no accent there;
- every name-valued template coming *from* the backend failed mobile's
  6-character hex parse and fell back to brand blue — so a seeded library
  showed four identical blue rows on the phone and four distinct colours on
  the web.

Mobile now reads and writes names, and `TemplateAccent.normalize()` maps the
legacy hex values onto the nearest name. **Existing hex rows repair themselves
the next time a template is saved.** A data migration is optional; if you want
the rows cleaned up eagerly rather than lazily, map:

    #159567 / #1f9d63 / #16a34a -> green
    #d97706 / #f79009           -> orange
    #7c3aed / #7a5af8           -> purple
    anything else               -> blue
