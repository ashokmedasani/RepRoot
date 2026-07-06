# frontend/src/app/pages/trainer-login/trainer-login.component.html

## What this file does

Renders the trainer login form.

## Why this file exists

Trainers need a dedicated page for entering username/email and password.

## Page or module

Trainer Login page.

## Important functions/classes/components

- Username or email field.
- Password field.
- Top success notice area for signup/password reset redirects.
- Required-field asterisk markers placed inline to the right of the field label.
- Continue button.
- Forgot password link.
- Top-right "New to CoachFlow? Sign up" link.
- Status message area.

## Data flow

Form fields use Angular two-way binding and submit through `verifyTrainerLogin`. One-time success notices display above the form.

## Connected files

- `frontend/src/app/pages/trainer-login/trainer-login.component.ts`
- `frontend/src/app/pages/trainer-login/trainer-login.component.scss`
- `frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.ts`

## Business logic

All visible login fields are mandatory and marked with `*`. The forgot password link routes to the trainer password reset page. Signup and password reset redirects can display a one-time top notice.

## Assumptions made

Login verification happens through the backend API.

## Future improvement notes

Add stronger recovery messaging after email delivery provider requirements are approved.
