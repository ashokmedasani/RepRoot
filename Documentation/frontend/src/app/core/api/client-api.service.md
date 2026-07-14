# frontend/src/app/core/api/client-api.service.ts

## 2026-07-13 targeted refinement

Adds Client Dashboard types/API access and nullable onboarding-source/reference fields used by the redesigned client portal.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Typed Angular HTTP client for the client portal: login, password change, profile, assigned templates, and tracking entries.

## Why this file exists

Clients now authenticate with a real token and interact with their own portal data instead of a static sessionStorage blob.

## Page or module

Angular core API services.

## Important functions/classes/components

- `login`: returns `token` plus the client record; the token is stored in sessionStorage as `client-auth-token`.
- `changePassword`: verifies the current password and clears `must_change_password`.
- `getMe`: profile, group, registration fields, and original lead submission.
- `getTemplates`: assigned templates including attached references.
- `getEntries` / `submitEntry`: entry history and template submission.
- `getProgress`: read-only progress notes shared by the trainer.

## Data flow

All authenticated methods send `Authorization: ClientToken <key>`. Entries and trainer-shared progress records feed the client template tabs.

## Connected files

- `frontend/src/app/pages/clients/client-login/client-login.component.ts`
- `frontend/src/app/pages/clients/client-change-password/client-change-password.component.ts`
- `frontend/src/app/pages/clients/client-profile/client-profile.component.ts`
- `backend/accounts/client_auth.py`

## 2026-07-13 production audit

Trainer directory records intentionally contain only trainer name and trainer code. `logout()` calls the server token-revocation endpoint.

The client dashboard summary contract now includes a distinct overdue schedule count while retaining the five required main KPIs.
