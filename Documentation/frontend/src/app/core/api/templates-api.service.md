# frontend/src/app/core/api/templates-api.service.ts

## What this file does

Typed Angular HTTP client for trainer-level tracking templates, standard-template adoption, per-client assignments, and tracking entries.

## Why this file exists

Templates moved from per-group localStorage to a backend, trainer-level model (max five, shared across all groups). Trainer pages need one focused client for the whole feature.

## Page or module

Angular core API services.

## Important functions/classes/components

- `getTemplates` / `getTemplate` / `createTemplate` / `updateTemplate` / `deleteTemplate` (payload carries `custom_fields` and `reference_ids`).
- `getStandardTemplates` / `adoptStandardTemplate`.
- `getAssignments` / `assignTemplate` / `unassignTemplate` per client.
- `getClientEntries` (filters template and month) and `updateEntry` (trainer edits).
- Interfaces: `TrackingTemplateRecord`, `TemplateField` (no required flag), `TemplateAssignmentRecord`, `TrackingEntryRecord`.

## Data flow

All methods send the trainer token header. Template records embed their attached references so the builder and client portal render them without extra calls.

## Connected files

- `frontend/src/app/pages/trainer/trainer-templates/trainer-templates.component.ts`
- `frontend/src/app/pages/trainer/trainer-tracking-template-create/trainer-tracking-template-create.component.ts`
- `frontend/src/app/pages/trainer/trainer-client-profile/trainer-client-profile.component.ts`
- `backend/accounts/views.py`

## Update: references shared per assignment

`TemplatePayload` no longer carries `reference_ids`. `assignTemplate` accepts optional `referenceIds`, and `updateAssignmentReferences(clientId, assignmentId, referenceIds)` edits an existing assignment's shared references. `TemplateAssignmentRecord` includes the shared `references`; `TrackingTemplateRecord.references` is optional and only populated for the client portal.
