# backend/accounts/views.py

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
