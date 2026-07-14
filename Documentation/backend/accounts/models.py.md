# backend/accounts/models.py

## 2026-07-13 immutable trainer audit reference

`TrainerProfile.internal_reference_code` is an automatically generated, immutable, unique `TRN-…` identifier. The editable trainer lookup/login code remains separate. Internal logs use username plus this stable reference so history survives username or trainer-code changes.

## 2026-07-13 targeted refinement

Adds distinct group-registration submissions, public group form slugs, onboarding source/method support, read-only client reference IDs, and nullable lead-source compatibility.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Defines database models for trainer account profile data and the Forms & Groups setup flow.

## Why this file exists

Django's built-in `User` model stores authentication and identity fields. `TrainerProfile` stores trainer-specific setup, profile, and portfolio data without mixing it into the auth table.

## Page or module

Backend accounts module for trainer signup, login, profile setup, Profile / Portfolio, public lead forms, groups, client registration forms, submitted leads, and client access records.

## Important functions/classes/components

- `TrainerProfile`: one-to-one profile linked to Django's user model.
- `profile_setup_completed`: controls whether a trainer must complete `/trainer/profile-setup`.
- File fields: store profile photo, certification upload, transformation photo, and training photo.
- `UNIVERSAL_CORE_FIELDS`: required First Name, Last Name, and Email Address fields reused by lead and client registration forms.
- `TrainerLeadForm`: one public lead form per trainer with a non-deletable public slug.
- `TrainerGroup`: trainer-owned client group with a five-group limit enforced by the API.
- `ClientRegistrationForm`: one registration form per group.
- `LeadSubmission`: submitted public form answers with generated applicant reference IDs.
- `ClientAccess`: converted client access record with trainer-scoped unique email and username.
- KPI lifecycle fields: `created_at`, `updated_at`, `status`, `converted_at`, `deleted_at`, and `is_active` are present where future aggregate reporting needs them.

## Data flow

Trainer signup creates a Django `User` and linked `TrainerProfile`. Forms & Groups APIs create the trainer's lead form, groups, group registration forms, lead submissions, and conversion records. Future KPI dashboards can aggregate by trainer, form, group, status, active flags, and dates without reading private answers.

## Connected files

- `backend/accounts/serializers.py`
- `backend/accounts/views.py`
- `backend/accounts/admin.py`
- `backend/accounts/migrations/0004_trainerprofile_setup_portfolio.py`
- `backend/accounts/migrations/0006_forms_groups_flow.py`
- `backend/accounts/migrations/0007_clientaccess_is_active_clientaccess_updated_at_and_more.py`

## Business logic

New trainer profiles start as incomplete. Forms & Groups setup only checks whether the trainer has at least one active lead form, then requires at least one active group and a client registration form for selected groups. Deleted lead submissions are soft deleted with `status='deleted'`, `is_active=false`, and `deleted_at`.

## Assumptions made

The first version stores one certification and one upload per media category. Multi-item galleries can be added later with related tables.

## Future improvement notes

Move portfolio media and certifications into separate models when approval, ordering, and multiple uploads are required.

## Update: templates, references, and client portal

- `ReferenceCategory` / `TrainerReference`: trainer resource library (video links are YouTube-only; files use `upload_to='trainer-references/'`).
- `TrackingTemplate`: trainer-level check-in template (max five per trainer, fields JSON without required flags, `standard_key` marks adopted standards, `references` M2M attaches curated resources).
- `TemplateAssignment`: which clients follow which template; unassigning deletes only the assignment.
- `TrackingEntry`: one client entry per template per date; keeps `template_name` snapshot and survives template deletion (SET_NULL).
- `ChatMessage`: trainer-client chat messages with sender and read flag.
- `ClientAuthToken`: opaque portal token per client (see `client_auth.py`).

## Update 2: references shared per assignment

`TrackingTemplate` no longer has a `references` field. `TemplateAssignment.references` (M2M to `TrainerReference`) now stores which references a trainer shared with a specific client for that template.

## Update 3: private trainer notes

`ClientAccess.trainer_notes` + `trainer_notes_updated_at`: private per-client notes visible only to the trainer (never serialized to the client portal).

## Update 4: trainer code

`TrainerProfile.trainer_code` (unique, chosen at profile setup, editable in Settings). Clients must supply this code plus username + password to log in, which scopes the client-username lookup to one trainer.
