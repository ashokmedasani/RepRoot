# frontend/src/app/pages/trainer-profile/trainer-profile.component.ts

## What this file does

Defines the trainer Profile component.

## Why this file exists

After profile setup is complete, trainers need a main page to manage profile identity, professional details, certification details, media, and public-facing profile content.

## Page or module

Trainer Profile page.

## Important functions/classes/components

- `TrainerProfileComponent`
- Reactive profile form
- `saveProfile()`
- `handleFileSelected()`
- Public preview helpers
- Global country and state/region dropdown data through `country-state-city`

## Data flow

The component loads the profile from the backend, redirects incomplete profiles back to setup, sends edits through `FormData`, and updates the preview after save.

## Business logic

Basic identity fields remain required. Professional details, certification, portfolio media, and links are optional profile-enrichment fields. Country and state values are saved as display names to preserve the existing backend shape.

## Connected files

- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `frontend/src/app/pages/trainer-profile/trainer-profile.component.html`
- `frontend/src/app/pages/trainer-profile/trainer-profile.component.scss`
- `backend/accounts/views.py`

## Future improvement notes

Split certifications and portfolio media into repeated sections when multiple entries are approved.
