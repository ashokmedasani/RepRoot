# backend/accounts/urls.py

## What this file does

Defines account and trainer API routes.

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
- `trainer/password-reset/request-otp/`
- `trainer/password-reset/verify-otp/`
- `trainer/password-reset/confirm/`

## API flow

Angular calls these routes through `TrainerAuthApiService`.

## Business logic

Profile routes are protected by token authentication in their view classes.

## Connected files

- `backend/accounts/views.py`
- `backend/config/urls.py`

## Future improvement notes

Move profile URLs to a dedicated trainer app if trainer features become large enough to split from account access.
