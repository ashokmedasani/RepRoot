# frontend/src/app/core/api/references-api.service.ts

## 2026-07-13 targeted refinement

Exposes configured reference usage and limit data returned by the backend.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Typed Angular HTTP client for the trainer references library (categories and references).

## Why this file exists

The References Library page previously stored everything in localStorage. This service persists categories and references server-side so templates can attach them and clients can receive them.

## Page or module

Angular core API services.

## Important functions/classes/components

- `getCategories` / `createCategory` / `updateCategory` / `deleteCategory`.
- `getReferences` / `createReference` / `updateReference` / `deleteReference`.
- `buildFormData`: sends references as multipart form data so PDF/image files upload as real files (tags serialized as a comma string).
- `ReferenceType` union mirrors the backend whitelist; videos are YouTube links only.

## Data flow

All methods send the trainer token header. File uploads land in Django media storage; responses include absolute `file_url` values.

## Connected files

- `frontend/src/app/pages/trainer/trainer-references/trainer-references.component.ts`
- `frontend/src/app/pages/trainer/trainer-tracking-template-create/trainer-tracking-template-create.component.ts`
- `backend/accounts/views.py`
