# frontend/src/app/pages/trainer-profile-setup/trainer-profile-setup.component.ts

## What this file does

Defines the mandatory first-login trainer profile setup component.

## Why this file exists

New trainers need to complete required identity/profile fields before using the main trainer profile area.

## Page or module

Trainer Profile Setup page.

## Important functions/classes/components

- `TrainerProfileSetupComponent`
- Reactive setup form
- `saveProfileSetup()`
- `handlePhotoSelected()`
- Global country and state/region dropdown data through `country-state-city`

## Data flow

The component loads existing profile data, pre-fills first and last name, validates required fields, sends `FormData` to the profile API, and routes to `/trainer/profile` after successful save.

## Business logic

Required fields are first name, last name, birth month, birth year, gender, country, and state/region. Profile photo, headline, and about me are optional. Country and state are saved as display names.

## Connected files

- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `frontend/src/app/pages/trainer-profile-setup/trainer-profile-setup.component.html`
- `frontend/src/app/pages/trainer-profile-setup/trainer-profile-setup.component.scss`
- `backend/accounts/views.py`

## Future improvement notes

Move location data behind a backend lookup API if server-side validation becomes necessary.
