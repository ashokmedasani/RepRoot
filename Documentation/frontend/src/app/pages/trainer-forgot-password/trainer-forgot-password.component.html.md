# frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.html

## What this file does

Renders the trainer password reset form.

## Why this file exists

The login page needs a dedicated recovery page instead of mixing reset fields into the login form.

## Page or module

Trainer Forgot Password page.

## Important functions/classes/components

- Top bar with app name and return-to-login action.
- Email field with Send OTP button.
- Missing-account Signup/Login guidance.
- Resend OTP link below the email field.
- OTP field with Verify Email, Verified, or Not verified state button.
- New password and confirm password fields.
- Field-level password, confirm-password, and OTP errors.
- Reset Password button.
- Status message area.

## Data flow

Form fields bind to `resetForm` in the TypeScript component. Button clicks call `requestOtp`, `verifyOtp`, and the form submit calls `resetPassword`. Inline email helper text shows OTP status, missing-account guidance, and resend countdown.

## Connected files

- `frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.ts`
- `frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.scss`
- `frontend/src/app/app.routes.ts`

## Business logic

All reset fields are mandatory and marked with a red `*`. The OTP must be verified before the password can be reset successfully, and wrong OTP errors display under the OTP field. Password must satisfy the platform password rule and Confirm Password must match. If no trainer account exists for the email, the page links to signup and login instead of requesting OTP.

## Assumptions made

The same premium auth layout used by trainer login/signup is acceptable for password reset.

## Future improvement notes

Add richer password strength and OTP attempt messaging after password policy is approved.
