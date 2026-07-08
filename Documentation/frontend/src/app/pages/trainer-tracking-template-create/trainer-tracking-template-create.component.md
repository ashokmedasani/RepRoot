# frontend/src/app/pages/trainer/trainer-tracking-template-create/trainer-tracking-template-create.component.ts

## What this file does

Trainer-level template builder for `/trainer/templates/create` and `/trainer/templates/:templateId/edit`: template details, a single flexible field list, and a reference picker.

## Why this file exists

Replaces the old per-group localStorage builder. Templates now save to the backend, have no mandatory fields, and carry a curated set of attached references.

## Page or module

Trainer Templates section.

## Important functions/classes/components

- `templateInfo` (name, purpose, cadence, accent) and `fields` (label, type, placeholder - no required toggle).
- `addField` / `removeField` / `moveField` for the field list.
- Reference picker: categories with checkboxes, search filter, `selectedReferenceIds` set.
- `saveTemplate` sends `custom_fields` and `reference_ids` to create or update.

## Data flow

Edit mode loads the template via `getTemplate` and pre-selects its attached references. The references library loads through `ReferencesApiService`.

## Connected files

- `frontend/src/app/core/api/templates-api.service.ts`
- `frontend/src/app/core/api/references-api.service.ts`
- `frontend/src/app/pages/trainer/trainer-templates/trainer-templates.component.ts`

## Update

The reference picker was removed from the builder - references are now shared per client at assignment time from the client profile. Save errors scroll the page to the message so failures are visible.
