# frontend/src/app/pages/trainer-profile-setup/trainer-profile-setup.component.html

## What this file does

Provides the HTML template for the mandatory trainer profile setup page.

## Why this file exists

It renders the warning message, required setup form, validation messages, loading state, improved photo upload/change controls, and save action.

## Page or module

Trainer Profile Setup page.

## Data flow

Template bindings read from the reactive form and call component methods for photo selection and saving.

## Business logic

The form displays only first-login setup fields and avoids certifications, forms, groups, clients, and references. Existing photos show as already available with a Change Photo action.

## Connected files

- `trainer-profile-setup.component.ts`
- `trainer-profile-setup.component.scss`
- `frontend/src/styles.scss`

## Future improvement notes

Add image validation once upload size/type rules are finalized.
