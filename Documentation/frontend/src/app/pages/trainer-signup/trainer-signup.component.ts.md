# frontend/src/app/pages/trainer-signup/trainer-signup.component.ts

## What this file does

Defines the standalone Angular component for trainer signup.

## Why this file exists

Trainer signup needs form state, OTP state, backend API calls, and account creation logic separate from the page template.

## Page or module

Trainer Signup page at `/trainer/signup`.

## Important functions/classes/components

- `TrainerSignupComponent`: owns signup form state and submits trainer account data.
- `requestEmailOtp`: sends a signup OTP request and starts the resend countdown.
- `verifyEmailOtp`: verifies the OTP and stores the backend email verification token.
- `verifyUsername`: checks username availability through the backend.
- `createTrainerAccount`: validates required fields and submits account creation data.
- `validateSignupFields`: runs frontend required-field, password-strength, confirm-password, username, and OTP checks.
- `applySignupApiErrors`: maps backend validation errors to the specific signup field.
- `clearSignupState`: clears signup form fields and OTP state after successful account creation.
- `formatApiError`: extracts readable backend validation messages.

## Data flow

The template binds form fields to `signupForm`. Username verification checks the backend before signup; available usernames show as status text and taken usernames show once as a field error. The Send OTP flow first calls the backend email availability check. If the email is available, it requests the OTP through Django. Successful OTP verification stores `emailVerificationToken`; account creation sends that token with the signup payload. Existing-email responses are surfaced once as Login and Forgot Password guidance before an OTP request is made. After successful signup, the component clears signup state, removes any old auth token, writes a one-time login notice, and redirects to `/trainer/login`.

## Connected files

- `frontend/src/app/pages/trainer-signup/trainer-signup.component.html`
- `frontend/src/app/pages/trainer-signup/trainer-signup.component.scss`
- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `backend/accounts/views.py`

## Business logic

All signup fields are mandatory except middle name. Username must be verified and available before account creation. OTP must be verified before account creation, and wrong OTP is shown under the OTP field. Password must be at least 8 characters and include 1 special character. Confirm Password must match Password. The Send OTP button is disabled after sending and the resend action appears as a separate link under the email field after 30 seconds. The Verify Email button changes state to `Verified` after backend confirmation or `Not verified. Try again` after a failed attempt. Signup does not collect birth month or birth year. Signup does not auto-login the trainer after account creation.

## Assumptions made

OTP delivery uses the Django console email backend during local testing.

## Future improvement notes

Add server-side resend throttling, OTP attempt limits, and password strength feedback before production.
