# frontend/src/app/pages/trainer/trainer-references/trainer-references.component.ts

## What this file does

References Library page: categories sidebar, searchable reference table, detail panel with YouTube streaming, and editors for references and categories.

## Why this file exists

The trainer's reusable resource library (YouTube videos, PDFs, images, documents, notes) that templates draw from when sending resources to clients.

## Page or module

Trainer References Library at `/trainer/references`.

## Important functions/classes/components

- Backed by `ReferencesApiService` (was localStorage); files upload as multipart instead of base64.
- `validateForm` enforces the YouTube-only rule for video references.
- `youtubeEmbedResourceUrl` sanitizes embed URLs for in-app streaming.
- `duplicateReference` copies metadata server-side.

## Data flow

Loads categories and references on init; saves refresh category counts. Reference view models map API records (`file_url`, `category_name`) onto the existing UI shape.

## Connected files

- `frontend/src/app/core/api/references-api.service.ts`
- `frontend/src/app/pages/trainer/trainer-tracking-template-create/trainer-tracking-template-create.component.ts`
