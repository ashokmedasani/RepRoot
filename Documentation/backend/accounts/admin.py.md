# backend/accounts/admin.py

## What this file does

Registers trainer profiles, recycled trainer accounts, and Forms & Groups records in Django admin.

## Why this file exists

Local development and admin review need visibility into trainer profile records, setup completion, forms, groups, submissions, and converted client access records.

## Page or module

Backend accounts module.

## Important functions/classes/components

- `TrainerProfileAdmin`: configures list display, search, and filters.
- `TrainerLeadFormAdmin`: exposes public slug, active flag, and trainer lead form records.
- `TrainerGroupAdmin`: exposes trainer groups and active flag.
- `ClientRegistrationFormAdmin`: exposes group registration forms and active flag.
- `LeadSubmissionAdmin`: exposes pending, approved, and deleted public submissions.
- `ClientAccessAdmin`: exposes converted client access records and active flag.

## Data flow

Admin users can inspect trainer profile records, lead forms, group setup, public submissions, client access records, and lifecycle fields used for future aggregate reporting.

## Connected files

- `backend/accounts/models.py`

## Business logic

No behavior is changed here. The admin only exposes records for review and local troubleshooting.

## Assumptions made

Admin access is for local and internal management only.

## Future improvement notes

Add read-only media previews and grouped fieldsets when admin maintenance becomes part of the production workflow.

## Update

Registered admin entries for `ReferenceCategory`, `TrainerReference`, `TrackingTemplate`, `TemplateAssignment`, `TrackingEntry`, `ChatMessage`, and `ClientAuthToken` (token key read-only).
