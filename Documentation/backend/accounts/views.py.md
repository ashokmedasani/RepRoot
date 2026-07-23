# backend/accounts/views.py

## 2026-07-15 UI, workflow, and bug fixes

Client password change now rotates the auth token and returns the fresh token in the response, fixing the post-change "Invalid token" login failure. Client password reset accepts an optional trainer-defined `password` (validated for strength) for consistency with manual client creation; a secure password is generated only when none is provided.

## 2026-07-13 Client Action Center follow-up

The existing trainer upcoming-reminders response now also returns trainer-owned pending client profile edits and a `pending_profile_edits` summary count. Each activity includes the client, group, request time, note, and number of actually changed editable fields. No endpoint or model was replaced.

## 2026-07-13 targeted refinement

Implements onboarding conversions and credential email, required schedule KPI windows, reference limits, Client Dashboard aggregation, and granular public trainer profile visibility.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Exposes API views for trainer account access, OTP verification, password reset, profile status, profile save/read, and Forms & Groups workflows.

## Why this file exists

The Angular frontend needs REST endpoints for signup/login, protected trainer profile workflows, Forms & Groups setup, and public lead form submission.

## Page or module

Backend accounts module.

## Important functions/classes/components

- `TrainerSignupView`: creates trainer accounts.
- `TrainerLoginView`: returns auth token and trainer account data.
- `TrainerProfileStatusView`: returns whether setup is complete.
- `TrainerProfileView`: supports `GET`, `POST`, and `PUT` for trainer setup/Profile data with multipart uploads.
- Password reset and email OTP views support existing forgot-password and signup flows.
- `FormsGroupsOverviewView`: returns lead form, groups, pending forms, approved forms, deleted forms, and group limits.
- `TrainerLeadFormView`: creates or edits the trainer's non-deletable public Form 1.
- `TrainerGroupListView`: creates trainer groups, up to five.
- `ClientRegistrationFormView`: creates or edits a group's mandatory client registration form.
- `PublicLeadFormView`: displays and accepts unauthenticated public lead submissions.
- `ClientAccessCreateView`: converts pending submissions into client access records and sends temporary credentials.
- `GroupClientAccessListView`: returns active client users for one trainer-owned group.

## API flow

- `GET /api/accounts/trainer/profile/status/`
- `GET /api/accounts/trainer/profile/`
- `POST /api/accounts/trainer/profile/`
- `PUT /api/accounts/trainer/profile/`
- `GET /api/accounts/trainer/forms-groups/`
- `POST /api/accounts/trainer/forms-groups/lead-form/`
- `POST /api/accounts/trainer/forms-groups/groups/`
- `POST /api/accounts/trainer/forms-groups/groups/<group_id>/registration-form/`
- `GET /api/accounts/trainer/forms-groups/groups/<group_id>/clients/`
- `DELETE /api/accounts/trainer/forms-groups/pending/<submission_id>/`
- `POST /api/accounts/trainer/forms-groups/pending/<submission_id>/create-client-access/`
- `GET|POST /api/accounts/public/forms/<public_slug>/`

Protected profile endpoints require DRF token authentication. Forms & Groups management endpoints return active records for trainer workflow screens.

## Business logic

Login itself still only authenticates. Forms & Groups setup does not check trainer profile completion; it only checks whether an active lead form exists and then drives group and registration form setup. Pending form deletion is a soft delete so future KPI dashboards can count deleted requests by status and `deleted_at`.

## Connected files

- `backend/accounts/serializers.py`
- `backend/accounts/urls.py`
- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `frontend/src/app/core/api/forms-groups-api.service.ts`

## Future improvement notes

Add object-level permissions and audit logging before production profile publishing.

## Update: templates, references, chat, and client portal

- References CRUD: `TrainerReferenceCategoryListView`/`DetailView` (delete blocked while references exist), `TrainerReferenceListView`/`DetailView` (multipart uploads, YouTube-only videos).
- Templates: `StandardTemplateListView`, `StandardTemplateAdoptView`, `TrackingTemplateListView`/`DetailView`; `MAX_TRACKING_TEMPLATES = 5` enforced on create and adopt.
- Assignments and entries: `ClientTemplateAssignmentListView`/`DetailView`, `ClientTrackingEntryListView` (filters `?template=`, `?month=YYYY-MM`), `TrainerTrackingEntryDetailView` (trainer edits mark `edited_by_trainer`).
- Chat: `TrainerClientChatView` and `ClientChatView` (REST polling with `?after=<id>`, marks the other side's messages read).
- Client portal (ClientTokenAuthentication): `ClientLoginView` now returns a token; `ClientPasswordChangeView`, `ClientMeView`, `ClientTemplateListView` (assigned templates with attached references), `ClientTrackingEntryView` (upsert per template and date).

## Update 2: references shared per assignment

- `ClientTemplateAssignmentListView.post` accepts `reference_ids` when assigning.
- `ClientTemplateAssignmentDetailView.put` updates an assignment's shared references (`set_assignment_references` helper scopes them to the trainer).
- `ClientTemplateListView` returns each template's references from the client's assignment, not the template.

## Update 3: trainer notes and trainer-recorded entries

- `ClientTrainerNotesView` (`PUT trainer/forms-groups/clients/<id>/notes/`) saves private notes with a timestamp; notes are returned by `ClientAccessDetailView` but never exposed to client endpoints.
- `ClientTrackingEntryListView.post` lets the trainer record an entry on behalf of a client (upsert per date, marked `edited_by_trainer`).

## Update 4: trainer code endpoints

- `TrainerCodeAvailabilityView` (`POST trainer/check-trainer-code/`) - live availability check.
- `TrainerCodeUpdateView` (`GET/PUT trainer/account/trainer-code/`) - view/change the code in Settings.

## Update 5: client progress read endpoint

- `ClientPortalProgressView` (`GET client/progress/`) exposes the authenticated client's trainer-shared progress records as read-only data for the client portal Progress tab.

## Update 6: schedules and trainer client editing

- `TrainerUpcomingRemindersView` now returns the next 10 pending schedules plus summary counts for total pending, due within 24 hours, due within 5 days, 7 days, and 10 days.
- `ClientAccessDetailView.put` lets the trainer update normal client profile fields and registration answers while keeping system values such as submission reference ID protected.
- API impact only; no database schema change.
- Testing performed: `python manage.py check`.

## 2026-07-13 production audit

- Public trainer payloads now honor every current visibility key and bridge legacy gallery, certification, and social-link fields into the client-facing contract.
- Trainer search returns only trainer name and trainer code.
- Authentication, OTP, trainer-directory, and public-registration endpoints use scoped rate limiting.
- Client password changes revoke existing client tokens, and the new logout endpoint revokes the active token.
- Trainer-managed Additional Details and client photos are validated before persistence; all client lookups remain trainer-owned.
- Current schedule summaries expose the required 24-hour and 7-day windows; the retired 5-day and 10-day values are no longer presented by the dashboard.

## 2026-07-13 overdue schedule organization

Trainer and client dashboard summaries now expose a separate `overdue` count. The 24-hour and 7-day windows count future schedules only, preventing overdue work from being counted twice. The nearest upcoming date also ignores overdue records.

## 2026-07-13 trainer data usage

Adds an authenticated read-only endpoint that returns total, database-content, and uploaded-file bytes for the current trainer only.
