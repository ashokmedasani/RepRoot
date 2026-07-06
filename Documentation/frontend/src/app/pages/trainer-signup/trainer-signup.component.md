# frontend/src/app/pages/trainer-signup/trainer-signup.component.ts

## What this file does

Defines the trainer signup page and submits the simplified signup data to the backend.

## Why this file exists

Trainer signup should be a separate page with the approved reduced field set.

## Page or module

Trainer Signup page.

## Important functions/classes/components

- `TrainerSignupComponent`: standalone signup form component.
- `verifyEmail`: requests an OTP through the backend.
- `verifyEmailOtp`: verifies the OTP and stores the temporary email verification token.
- `verifyUsername`: checks username availability through the backend.
- `createTrainerAccount`: validates required fields and submits signup data.
- Terms and privacy dialog handlers.

## Data flow

Signup fields flow from the template into component state, then into `TrainerAuthApiService`, then to Django REST Framework. Email OTP verification must complete before signup sends the final account creation request.

## Connected files

- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `frontend/src/app/pages/trainer-signup/trainer-signup.component.html`
- `frontend/src/app/pages/trainer-signup/trainer-signup.component.scss`
- `backend/accounts/serializers.py`

## Business logic

All signup fields are mandatory except middle name. Email OTP verification is required before account creation. The form asks for birth month and birth year instead of full date of birth.

## Assumptions made

The signup format intentionally stays minimal for this design pass.

## Future improvement notes

Add legal consent language later if required before production.
