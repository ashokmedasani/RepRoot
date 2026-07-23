# UI, workflow, and bug fixes — 2026-07-15

## 1. Username validation
- All username creation paths (trainer signup, availability check, client creation/approval) allow only letters, numbers, `.` and `-`. Spaces and other special characters are rejected with: "Only letters, numbers, '.' and '-' are allowed."
- Enforced on the backend (`validate_username_charset` in `accounts/serializers.py`) and inline in the trainer signup form. Existing usernames (for example seeded ones containing `_`) still log in — the rule applies to new usernames only.
- Mobile auto-suggested usernames use `first.last` instead of `first_last`.

## 2. Form → Group setup flow
- After creating a group, the app continues automatically to the Group Registration Form setup. The previous navigation passed `'client-form/create'` as one URL-encoded route segment, which never matched the route and stranded the trainer until a refresh.

## 3. Group registration form fields (synchronization chosen)
- First-time registration form setup pre-populates the builder with the Lead Form's custom fields, so trainers never rebuild the same questions. If the lead form has no custom fields, the universal template is used as before. Saved registration forms are always shown as saved.

## 4. Form builder action button
- The per-field action button is now labeled "Edit" (was "Settings"). Edit, Move Up, Move Down, Duplicate, and Delete are all available on each field card.

## 5. Template delete refresh
- Deleting a template updates the list immediately. Root cause: the model updated after the confirmation dialog await, but no change-detection cycle followed, so the deleted card stayed until a manual refresh. The templates page now runs explicit change detection after every list reload.

## 6. Template builder layout
- Create/Edit Template: Template Details and the Summary card share a top row; the Field Builder spans the full available width below as the primary editing area.

## 7–8. Dashboard
- KPI cards show only the actual value (no "/ limit" suffix).
- Activity order: Pending Requests (always-visible panel) → Client Tracking Center (schedule overview, attention KPIs, upcoming schedules) → Recent Activity accordion (recent clients, recent templates).

## 9. Client login "Invalid token" bug
- Root cause: changing the password deletes all client auth tokens (correct), but no replacement was issued, so the app kept using a dead token and every request failed with "Invalid token".
- Fix: the change-password endpoint now rotates and returns a fresh token; web and mobile store it and continue the session. Verified end-to-end: login with temporary password → change password → old token 401s, new token works, re-login with the new password succeeds.

## 10. Password generation consistency (Option A)
- The trainer defines the temporary password in both places: manual client creation (already) and password reset (new — the reset dialog prompts for a password with a generated suggestion; backend validates strength). Automatic generation remains only as a fallback when no password is sent.

## Testing performed
- Backend: `manage.py check` clean; all 11 accounts tests pass; direct API tests for username charset, token rotation, and trainer-defined reset passwords.
- Web (live browser): group create auto-continues to registration setup; builder prefilled with lead-form fields; "Edit" label present; template delete updates instantly with success message; field builder measured full-width; dashboard KPI text and section order verified.
- Both Angular apps (`frontend`, `mobile`) build with zero errors.

## Known issues / notes
- The missed change-detection pattern fixed on the Templates page (updates after a confirmation-dialog await) could exist on other pages that combine the confirmation dialog with in-place list updates; none showed the symptom during this pass, but flagging for future audit.
- The trainer plan currently allows 5 groups; testing created "Group 5" with a registration form synced from the lead form — rename and reuse it, since the Starter plan group limit is now reached.

## Full new-account diagnostics (later on 2026-07-15)

Two fresh trainer accounts were created end to end — one on the web portal, one in the mobile app — exercising signup, OTP, profile setup, lead form, group, registration form, templates, references, manual client creation, and the client first-login password flow.

Fixed during diagnostics:
- Web: a background chat-unread poll returning an error no longer hijacks the page to the global error view (this threw a brand-new trainer onto a 404 page right after profile setup).
- Mobile: signup/login now route incomplete profiles to a guided profile-setup mode (name, trainer code, gender, birth month/year, country, state) before the dashboard, matching the web's required first-login step. Previously a mobile-created trainer reached the dashboard with no trainer code, so their clients could never log in.
- Mobile profile edit gained the missing setup fields (trainer code, gender, birth month/year, state) and client-side required-field messages.
- Removed unused back-compat aliases from mobile API services (dead code).
