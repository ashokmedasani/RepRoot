# frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.scss

## What this file does

Styles the trainer password reset page.

## Why this file exists

The reset form needs a polished, responsive layout consistent with trainer login and signup.

## Page or module

Trainer Forgot Password page.

## Important functions/classes/components

- `.auth-page`: full-page themed background.
- `.auth-topbar`: app name and login navigation.
- `.auth-card`: centered rounded reset form container.
- `.input-with-button`: responsive email/OTP field plus action button layout.
- `.required`: red required-field marker that stays red across themes.
- `.field-help`: inline OTP, resend, and missing-account guidance.
- `.text-link`: resend action styling.
- `.success-text` and `.error-text`: verified and retry messaging.
- Compact aligned auth-card, input, and fixed-width action button dimensions.
- Field-level error message styling.

## Data flow

No data flows through this stylesheet.

## Connected files

- `frontend/src/app/pages/trainer-forgot-password/trainer-forgot-password.component.html`
- `frontend/src/styles.scss`

## Business logic

None.

## Assumptions made

Theme variables from `styles.scss` provide all page colors.

## Future improvement notes

Extract shared auth form styles after more authentication pages are finalized.
