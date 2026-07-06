# frontend/src/app/core/api/trainer-auth-api.service.ts

## What this file does

Provides Angular HTTP methods for trainer authentication, OTP/password reset, profile status, profile setup, and Profile / Portfolio save/read.

## Why this file exists

Centralizing trainer API calls keeps components focused on UI state and form handling.

## Page or module

Frontend core API layer for trainer access and profile pages.

## Important functions/classes/components

- `TrainerAuthApiService`
- `login()`
- `getProfileStatus()`
- `getProfile()`
- `saveProfile()`
- OTP and password reset request/verify methods

## API flow

Profile APIs send the local `trainer-auth-token` as a DRF `Token` authorization header. Profile saves use `FormData` so image/PDF uploads can be sent with text fields.

## Business logic

The service does not decide routing. It exposes `profile_setup_completed` so login and profile components can route correctly.

## Connected files

- `frontend/src/app/pages/trainer-login/trainer-login.component.ts`
- `frontend/src/app/pages/trainer-profile-setup/trainer-profile-setup.component.ts`
- `frontend/src/app/pages/trainer-profile/trainer-profile.component.ts`
- `backend/accounts/views.py`

## Future improvement notes

Move token handling into an HTTP interceptor when more protected APIs are added.
