# frontend/src/app/pages/trainer-profile/trainer-profile.component.html

## What this file does

Provides the HTML template for the Profile page.

## Why this file exists

It renders the top trainer navigation, LinkedIn-style profile header, editable profile sections, improved photo upload/change controls, save messages, and public profile preview.

## Page or module

Trainer Profile page.

## Data flow

Template bindings read from the reactive profile form and call component handlers for save and upload changes.

## Business logic

Navigation includes a real Forms & Groups link after that page was implemented. Existing profile photos are shown in the left profile-header photo position with a clear Change Photo action.

## Connected files

- `trainer-profile.component.ts`
- `trainer-profile.component.scss`
- `frontend/src/app/pages/trainer-forms-groups/trainer-forms-groups.component.ts`
- `frontend/src/styles.scss`

## Future improvement notes

Replace inactive navigation labels with real routes after those modules are approved.
