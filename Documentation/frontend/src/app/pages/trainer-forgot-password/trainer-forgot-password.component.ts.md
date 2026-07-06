# frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.ts

## What this file does

Defines the standalone Angular component for trainer password reset.

## Why this file exists

Trainers need a way to recover access when they forget their password.

## Page or module

Trainer Forgot Password page at `/trainer/forgot-password`.

## Important functions/classes/components

- `TrainerForgotPasswordComponent`: stores form state and calls password reset API methods.
- `requestOtp`: checks whether the trainer email exists and requests a six-digit reset OTP.
- `verifyOtp`: verifies the OTP and stores the temporary reset token.
- `resetPassword`: submits the reset token and new password.
- `sendResetOtpToExistingEmail`: sends or resends reset OTP after the email existence check passes.
- `applyResetApiErrors`: maps backend password reset validation errors to the specific field.
- `clearResetState`: clears reset form fields and OTP state after password reset.
- `formatApiError`: extracts readable backend validation messages.

## Data flow

The component captures email, OTP, new password, and confirm password through Angular forms. It first checks email availability through `TrainerAuthApiService`; if no trainer account exists, the page shows Signup/Login guidance. If the trainer account exists, it requests the reset OTP, stores the returned reset token after OTP verification, and then submits the token with the new password. After reset, it writes a one-time login notice and redirects to `/trainer/login`.

## Connected files

- `frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.html`
- `frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.scss`
- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `backend/accounts/views.py`

## Business logic

Email, OTP, password, and confirm password are required. Password must be at least 8 characters and include 1 special character. Confirm Password must match Password before the reset request is sent. Wrong OTP displays under the OTP field. Send OTP stays disabled after sending, resend appears separately after 30 seconds, and OTP verification changes to `Verified` or `Not verified. Try again`. The backend remains responsible for validating the trainer email and reset token.

## Assumptions made

Local testing uses the Django console email backend, so the OTP appears in the backend terminal.

## Future improvement notes

Add password strength guidance and stronger rate-limit feedback before production.
