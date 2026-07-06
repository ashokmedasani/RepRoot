# frontend/src/app/pages/trainer-access/trainer-access.component.ts

## What this file does

Defines the trainer access choice page.

## Why this file exists

Trainer login and signup should be separate pages, so this route gives trainers a clear choice before opening either form.

## Page or module

Trainer Access page.

## Important functions/classes/components

- `TrainerAccessComponent`: standalone Angular route component.

## Data flow

No form data flows through this component. It routes users to login or signup.

## Connected files

- `frontend/src/app/pages/trainer-access/trainer-access.component.html`
- `frontend/src/app/pages/trainer-access/trainer-access.component.scss`
- `frontend/src/app/app.routes.ts`

## Business logic

None. This is a navigation page only.

## Assumptions made

Trainer login and signup should not live inside the Client Management selection page.

## Future improvement notes

Add role-specific help text after onboarding requirements are approved.
