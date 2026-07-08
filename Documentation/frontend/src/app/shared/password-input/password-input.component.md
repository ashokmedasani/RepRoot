# frontend/src/app/shared/password-input/password-input.component.ts

## What this file does

Reusable password field with a show/hide (eye) toggle, implementing ControlValueAccessor so it drops into every ngModel form.

## Why this file exists

No password field in the app had a visibility toggle. One shared component replaces all 13 plain password inputs (trainer login/signup/forgot-password/account-settings, client-access creation, client login/change-password).

## Connected files

- Used by trainer-login, trainer-signup, trainer-forgot-password, trainer-account-settings, trainer-forms-groups, client-login, client-change-password.
