# frontend/src/app/pages/trainer/trainer-client-profile/trainer-client-profile.component.ts

## What this file does

The client profile a trainer sees: compact hero, single Account & Access dialog, merged intake details, template assignment, editable tracking entries, computed insights, and real chat.

## Why this file exists

Consolidates the previously duplicated identity sections into one dialog and adds the tracking workflow around each client.

## Page or module

Trainer client profile at `/trainer/clients/:clientId`.

## Important functions/classes/components

- `openAccountDialog` / `resetClientPassword`: identity plus password reset in one dialog.
- `buildIntakeDetails`: merges registration answers with non-duplicate lead-form answers.
- `assignTemplate` / `unassignTemplate`: flexible per-client template management (entries always kept).
- `startEntryEdit` / `saveEntryEdit`: trainer edits any entry; backend marks `edited_by_trainer`.
- Insights: `buildNumericTrends` (SVG sparkline series), `buildConsistency` (30-day dots), `recentNotes` (how the client is feeling by date).

## Data flow

Loads profile, trainer templates, assignments, and entries in parallel; insights recompute whenever entries or templates arrive.

## Connected files

- `frontend/src/app/core/api/forms-groups-api.service.ts`
- `frontend/src/app/core/api/templates-api.service.ts`
- `frontend/src/app/shared/chat-panel/chat-panel.component.ts`
