# backend/accounts/migrations/0008_clientauthtoken_referencecategory_trainerreference_and_more.py

## What this file does

Creates the tables for the references library, trainer-level tracking templates, per-client template assignments, client tracking entries, trainer-client chat messages, and client auth tokens.

## Why this file exists

Templates and references previously lived only in browser localStorage; this migration moves them server-side and adds the client portal data model.

## Page or module

Backend accounts module.

## Important functions/classes/components

- `ReferenceCategory` and `TrainerReference` (references library, PROTECT on category delete).
- `TrackingTemplate` with `references` many-to-many (max five per trainer enforced in views).
- `TemplateAssignment` unique per (client, template).
- `TrackingEntry` unique per (client, template, entry_date); template FK is SET_NULL with a name snapshot so history survives template deletion.
- `ChatMessage` indexed by (client, created_at).
- `ClientAuthToken` one-to-one with `ClientAccess`.

## Data flow

Applied with `python manage.py migrate accounts`.

## Connected files

- `backend/accounts/models.py`
