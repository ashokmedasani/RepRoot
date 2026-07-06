# frontend/src/app/pages/trainer-login/trainer-login.component.ts

## What this file does

Controls the trainer login page.

## Why this file exists

Trainers need to authenticate before accessing setup or profile pages.

## Page or module

Trainer login page.

## Important functions/classes/components

- `TrainerLoginComponent`
- `verifyTrainerLogin()`
- `routeAfterLogin()`

## Data flow

The component sends username/email and password to the backend. On success it stores the auth token, requests profile setup status, then routes to `/trainer/profile-setup` or `/trainer/profile`.

## Business logic

New or incomplete trainers must finish profile setup before reaching the Profile / Portfolio page.

## Connected files

- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `frontend/src/app/app.routes.ts`
- `backend/accounts/views.py`

## Future improvement notes

Move protected routing into guards when the trainer dashboard and additional app sections are created.
