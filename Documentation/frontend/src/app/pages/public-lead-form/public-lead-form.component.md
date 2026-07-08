# frontend/src/app/pages/public-lead-form/public-lead-form.component.ts

## What this file does

Controls the unauthenticated public trainer lead form page.

## Why this file exists

Potential clients need to fill Form 1 through a public share link and receive a reference ID after submission.

## Page or module

Public lead form page.

## Important functions/classes/components

- Loads a public form by slug.
- Builds an answer object for all configured fields.
- Submits answers to the backend.
- Displays the generated applicant reference ID after successful submission.
- Renders richer field types including phone, dropdown, checkbox, radio, date, location, and address.

## Connected files

- `public-lead-form.component.html`
- `public-lead-form.component.scss`
- `frontend/src/app/core/api/forms-groups-api.service.ts`
