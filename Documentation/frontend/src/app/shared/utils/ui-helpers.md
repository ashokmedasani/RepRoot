# frontend/src/app/shared/utils/ui-helpers.ts

## What this file does

Small shared UI helpers: `initialsFor(firstName, lastName)` and `formatApiError(error, fallback)`.

## Why this file exists

These helpers were copy-pasted across several trainer components; the shared module removes the duplication.

## Page or module

Shared frontend utilities.

## Data flow

`formatApiError` unwraps DRF error payloads (message, error string, or field-error maps) into one display string.

## Connected files

- Used by trainer client profile, group users, references, templates, builder, chat panel, and client portal pages.
