# Completion Summary — Fixes after 1 Test Launch

Covers work against `Documentation/Fixes after 1 Test Launch.docx`, done in priority order across frontend and backend (mobile_flutter excluded per instruction).

## Status

Completed: Issue 001, Priorities 1–11, shared items 22–24 (loading/empty/error states), items 25–27.

Not started: none from the doc's numbered list. One related-but-out-of-scope gap was found and is documented below rather than fixed silently.

## Files changed

**Backend** — `accounts/serializers.py`, `accounts/google_oauth.py` (new), `accounts/views.py`, `accounts/views_scheduling.py`, `accounts/views_payments.py`, `accounts/models.py`, `accounts/settings.py` (config/settings.py), `accounts/urls.py`, `accounts/tests.py`, migration `0025_professionalprofile_google_linked_at_and_more.py`.

**Frontend** — professional signup/login/forgot-password/account-settings components; new shared `password-requirements` and `google-signin-button` components; `professional-profile-form`, `professional-dashboard`, `form-field-builder`, `professional-client-form-create`, `professional-group-users`, `professional-schedule`, `professional-client-profile`, `client-payments-tab`, `professional-payment-settings`, `client-payments-panel`, `client-profile` (client portal), `professional-forms-groups`; `payments-api.service.ts`, `forms-groups-api.service.ts`, `scheduling-api.service.ts`, `professional-auth-api.service.ts`, `client-api.service.ts`; `write-app-config.mjs` / `app-config.js`; `render.yaml`.

Full diff is in the working tree / git history — this list is areas, not a line-by-line log.

## APIs changed

- New: `POST professional/auth/google/`, `DELETE professional/profile/photo/`, `POST professional/forms-groups/groups/<id>/registration-submissions/<id>/decline/`, `POST professional/scheduling/availability-windows/copy/`.
- Changed behavior: `PUT professional/payments/notifications/` and `PUT client/payments/notifications/` now take `{request_id}` (mark one request's notifications read) or `{mark_all: true}`, instead of always marking everything read; `GET` on those same endpoints now also returns an `items` list, not just a count. `PaymentRequestDetailView` and `ClientPaymentRequestDetailView` (the "view one request" endpoints) now auto-clear that request's unread notifications as a side effect of being viewed, mirrored into both `PaymentNotification` and `ActivityNotification` so the dashboard bell and the Payments tab never disagree.
- Unchanged but newly *used* by the frontend: `updateLeadFormStatus` / `saveLeadMeetingSettings` already accepted an optional `form_id` — the multi-lead-form dropdown (item 27) now actually passes it, instead of always operating on the oldest form.

## Database migrations

One: `0025_professionalprofile_google_linked_at_and_more.py`, adding `google_sub` and `google_linked_at` to `ProfessionalProfile`. **This must be applied and the backend restarted on any environment before this branch is used** — it was still unapplied on the local dev DB partway through this session and caused every authenticated professional endpoint to 500 (confirmed live and fixed by running `python manage.py migrate`).

## Environment variables required

`GOOGLE_OAUTH_CLIENT_ID` — optional. Google sign-in stays inactive (button hidden, no crash) until it's set; see `Documentation/GOOGLE_SIGNIN_SETUP.md`. No other new env vars.

## Test cases completed

- Backend: all new/changed logic covered by `accounts/tests.py` — Google auth (new/returning/linking/unverified-email), photo removal, group registration seeding + decline, availability overlap + copy, payment-notification unread/mark-read/mark-all/cross-system-sync (7 new tests specifically for priority 11). All run green against an in-memory SQLite DB this session; spot-re-ran `ProfessionalLifecycleTests`, `WorkflowRefinementTests`, `ProfessionalGoogleAuthTests`, `ProfessionalAvailabilityWindowTests` as a regression pass after all edits — no failures.
- One historical test failure used a now-obsolete internal plan label. That observation is retained only as test history and must not be treated as current plan policy; see `Documentation/PLAN_AND_BILLING_DRAFT.md`.
- Frontend: `tsc --noEmit` run clean after every batch of edits (10+ times this session, most recently at the very end).
- Live verification: ran the actual local app through a browser against the local backend (after the migration fix above) and visually confirmed, at desktop width: dashboard KPIs, Pending Users tab, Payments tab unread badges, availability copy-schedule, Private Notes full-width textarea, payment-request validation + single Add-button, Plan & Billing (Data usage button, collapsed Membership dropdown, currency formatting, no manual currency toggle), Integrated Payments "Coming soon", and the single-lead-form layout preserved.

## Unresolved risks / things I did not fix

1. **Found and fixed a live-breaking bug during this session's own browser verification**: the new Google sign-in button, when no `GOOGLE_OAUTH_CLIENT_ID` is configured (the current state everywhere until you set it up), was emitting its `unavailable` event synchronously during `ngOnInit`, which flipped a parent template's `@if` mid-render and threw Angular's NG0100 — crashing the login, signup, and forgot-password pages to the site's generic error screen. Fixed by deferring that emit a tick (`google-signin-button.component.ts`). Confirmed fixed live on all three pages. This would have blocked every sign-in until Google credentials were added, so it's worth double-checking in your own testing once you pull this.
2. **Lead-submission-to-form mapping**: `LeadSubmission` records don't currently carry which of a professional's lead forms they came from. For a professional with only one form this is invisible; for one with 2–3 forms (item 27's new dropdown makes this possible) with *different custom fields per form*, the "assign submission to client" screen (`professional-form-request-detail`) always uses the oldest form's field list, which could mismap answers if a submission came from a different form. Not part of what item 27 asked for, so I didn't touch it — flagging it as a natural follow-up if you use multiple lead forms with different fields.
3. **Responsive breakpoints**: couldn't get live mobile-viewport screenshots this session (the browser tool's window-resize didn't take effect in this environment). Did a code-level pass instead: found no repeat of the "missing width rule" bug class that caused the Private Notes issue, but breakpoint values across page-level `.scss` files are inconsistent (values from 520px to 1320px, no shared 2–3 tier system) — not broken, but a real contributor to the "pages feel different" complaint. Left alone rather than blind-editing ~20 files without being able to see the result.
4. Priority 5's deeper multi-lead-form-to-group auto-population/conflict-handling engine (the "8 items" middle part of that priority) was explicitly identified early in this session as a separate, unbuilt, greenfield feature and intentionally not attempted — the scoped bug (auto-copying fields) was fixed instead, as noted in an earlier checkpoint.
