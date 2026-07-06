# backend/accounts/admin.py

## What this file does

Registers trainer profiles in Django admin.

## Why this file exists

Local development and admin review need visibility into trainer profile records and setup completion.

## Page or module

Backend accounts module.

## Important functions/classes/components

- `TrainerProfileAdmin`: configures list display, search, and filters.

## Data flow

Admin users can inspect trainer profile records created during signup and updated during setup/Profile editing.

## Connected files

- `backend/accounts/models.py`

## Business logic

No behavior is changed here. The admin only exposes profile setup status and profile metadata for review.

## Assumptions made

Admin access is for local and internal management only.

## Future improvement notes

Add read-only media previews and grouped fieldsets when admin maintenance becomes part of the production workflow.
