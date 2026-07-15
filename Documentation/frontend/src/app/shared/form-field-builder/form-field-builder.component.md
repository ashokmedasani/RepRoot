# frontend/src/app/shared/form-field-builder/form-field-builder.component.ts

## 2026-07-15 UI, workflow, and bug fixes

The per-field action button is labeled 'Edit' (was 'Settings'); Move Up, Move Down, Duplicate, and Delete remain alongside it.

## What this file does

Controls the reusable custom field builder used by guided Forms & Groups setup pages.

## Why this file exists

Lead form creation and group client form creation need the same dynamic field editor and realistic field previews.

## Page or module

Shared Angular form builder UI.

## Important behavior

- Adds and removes custom fields.
- Supports text, email, phone, number, dropdown, checkbox, radio, date, location, and address field types.
- Stores choice options as field metadata.
- Shows a live preview that resembles the real input type instead of rendering every field as text.

## Connected files

- `frontend/src/app/pages/trainer-lead-form-create/trainer-lead-form-create.component.ts`
- `frontend/src/app/pages/trainer-client-form-create/trainer-client-form-create.component.ts`
- `frontend/src/app/core/api/forms-groups-api.service.ts`
