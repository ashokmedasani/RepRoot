# backend/accounts/views.py

## What this file does

Exposes API views for trainer account access, OTP verification, password reset, profile status, and profile save/read.

## Why this file exists

The Angular frontend needs REST endpoints for signup/login and protected trainer profile workflows.

## Page or module

Backend accounts module.

## Important functions/classes/components

- `TrainerSignupView`: creates trainer accounts.
- `TrainerLoginView`: returns auth token and trainer account data.
- `TrainerProfileStatusView`: returns whether setup is complete.
- `TrainerProfileView`: supports `GET`, `POST`, and `PUT` for trainer setup/Profile data with multipart uploads.
- Password reset and email OTP views support existing forgot-password and signup flows.

## API flow

- `GET /api/accounts/trainer/profile/status/`
- `GET /api/accounts/trainer/profile/`
- `POST /api/accounts/trainer/profile/`
- `PUT /api/accounts/trainer/profile/`

Protected profile endpoints require DRF token authentication.

## Business logic

Login itself still only authenticates. The frontend calls profile status after login and routes incomplete profiles to setup.

## Connected files

- `backend/accounts/serializers.py`
- `backend/accounts/urls.py`
- `frontend/src/app/core/api/trainer-auth-api.service.ts`

## Future improvement notes

Add object-level permissions and audit logging before production profile publishing.
