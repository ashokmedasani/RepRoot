# backend/accounts/urls.py

## 2026-07-13 targeted refinement

Registers manual client creation, public group registration, and Client Dashboard API routes without replacing existing endpoints.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Defines account, trainer, Forms & Groups, and public form API routes.

## Why this file exists

Routes keep account API endpoints grouped under `api/accounts/`.

## Page or module

Backend accounts module.

## Important routes

- `trainer/check-email/`
- `trainer/request-email-otp/`
- `trainer/verify-email-otp/`
- `trainer/check-username/`
- `trainer/signup/`
- `trainer/login/`
- `trainer/profile/status/`
- `trainer/profile/`
- `trainer/forms-groups/`
- `trainer/forms-groups/lead-form/`
- `trainer/forms-groups/groups/`
- `trainer/forms-groups/groups/<group_id>/registration-form/`
- `trainer/forms-groups/groups/<group_id>/clients/`
- `trainer/forms-groups/pending/<submission_id>/`
- `trainer/forms-groups/pending/<submission_id>/create-client-access/`
- `public/forms/<public_slug>/`
- `trainer/password-reset/request-otp/`
- `trainer/password-reset/verify-otp/`
- `trainer/password-reset/confirm/`

## API flow

Angular calls account routes through `TrainerAuthApiService` and Forms & Groups routes through `FormsGroupsApiService`.

## Business logic

Trainer profile and Forms & Groups management routes are protected by token authentication. Public form fetch and submit routes allow unauthenticated applicants.

## Connected files

- `backend/accounts/views.py`
- `backend/config/urls.py`

## Future improvement notes

Move profile URLs to a dedicated trainer app if trainer features become large enough to split from account access.

## Update: templates, references, chat, and client portal routes

- `trainer/references/categories/`, `trainer/references/` (+ detail routes).
- `trainer/templates/standard/`, `trainer/templates/adopt-standard/`, `trainer/templates/` (+ detail).
- `trainer/forms-groups/clients/<id>/assignments/` (+ detail), `.../entries/`, `trainer/entries/<id>/`, `trainer/clients/<id>/chat/`.
- Client portal: `client/change-password/`, `client/me/`, `client/templates/`, `client/entries/`, `client/chat/`.

## Update 3

Added `trainer/forms-groups/clients/<id>/notes/`.

## Update 4

Added `trainer/check-trainer-code/` and `trainer/account/trainer-code/`.

## Update 5

Added `client/progress/` for read-only client portal progress notes.

## 2026-07-13 production audit

Added `client/logout/` so client portal sign-out revokes the server-side token instead of only clearing browser state.

## 2026-07-13 trainer data usage

Adds `trainer/data-usage/` for the shared trainer sidebar indicator.
