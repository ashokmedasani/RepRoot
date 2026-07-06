# frontend/src/app/pages/trainer-signup/trainer-signup.component.html

## What this file does

Renders the trainer signup form.

## Why this file exists

Trainers need a dedicated signup page separate from login.

## Page or module

Trainer Signup page.

## Important functions/classes/components

- Username field with database verification, selected-username availability message, and single field-error display for taken usernames.
- Email ID field with Send OTP button.
- Existing-email Login and Forgot Password guidance displayed once under the email field.
- Resend OTP link under the email field.
- OTP field with Verify Email, Verified, or Not verified state button.
- Password and Confirm Password fields.
- OTP helper text below the email field.
- Password field.
- First name field.
- Optional middle name field.
- Last name field.
- Username field with verification.
- Birth month field.
- Required-field asterisk markers placed inline to the right of the field label.
- Create Account button.

## Data flow

Form fields use Angular two-way binding and submit through `createTrainerAccount`.

## Connected files

- `frontend/src/app/pages/trainer-signup/trainer-signup.component.ts`
- `frontend/src/app/pages/trainer-signup/trainer-signup.component.scss`

## Business logic

All fields are mandatory and marked with `*` except middle name. Username must be verified before account creation. OTP must be verified before account creation and wrong OTP errors display under the OTP field. Password must satisfy the platform password rule and Confirm Password must match. After sending OTP, Send OTP remains disabled, resend is shown separately under the email field after 30 seconds, and helper text tells the trainer to submit the OTP. If email already exists in the database, the page links the trainer to login or forgot password. Birth month and birth year are not collected.

## Assumptions made

Client account creation remains future scope.

## Future improvement notes

Add password strength feedback and richer OTP attempt messaging after password policy is approved.
