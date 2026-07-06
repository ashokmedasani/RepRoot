# backend/accounts/serializers.py

## What this file does

Defines Django REST Framework serializers for trainer authentication, OTP flows, password reset, profile status, profile setup, and Profile / Portfolio data.

## Why this file exists

Serializers validate API input, convert model data to API responses, and keep view classes thin.

## Page or module

Backend accounts module for Page 2 trainer access and trainer profile pages.

## Important functions/classes/components

- `TrainerSignupSerializer`: creates Django `User` and linked `TrainerProfile`.
- `TrainerLoginSerializer`: authenticates by username or email.
- `PasswordResetConfirmSerializer`: validates reset token and updates password.
- `TrainerProfileStatusSerializer`: returns `profile_setup_completed`.
- `TrainerProfileSerializer`: reads and writes setup/Profile fields, updates first and last name on the linked user, and returns media URLs.

## Data flow

Frontend sends auth/profile data to the API. Serializers validate the request, update the `User` and `TrainerProfile`, then return normalized response data.

## Business logic

Profile setup requires first name, last name, gender, birth month, birth year, country, and state. Saving a profile marks setup as completed.

## Connected files

- `backend/accounts/models.py`
- `backend/accounts/views.py`
- `frontend/src/app/core/api/trainer-auth-api.service.ts`

## Future improvement notes

Split portfolio media and certifications into nested serializers when they become multi-record features.
