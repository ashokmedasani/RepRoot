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

## Update: share references per assignment

Each assignment row shows how many references are shared and a Share References button that opens a category-grouped picker dialog (search + checkboxes). Assigning a template opens the dialog automatically so the trainer can share the relevant references right away; selections save via `updateAssignmentReferences`.

## Update: FitCoach-style two-panel layout

Left column: identity card (avatar, group link, contact info from intake answers, Edit User dialog), private Trainer Notes card (edit in place, last-updated stamp), clickable Assigned Templates rows, Client Activity stats (total entries this month, last entry, streak, completion %) with recent entries, and chat. Right column: template detail panel with Overview (shared reference cards, template notes, structure, today + 7-day trend table), Data Entries (per-template table with edit), and Progress (consistency strip, numeric trends, client notes) tabs, plus Share References and Add Entry (trainer-recorded, upserts per date) actions.

## Update 2: split into two pages

The template detail panel moved to its own page (`trainer-client-template`). The client profile is now a single centered column: identity card, private Trainer Notes, Assigned Templates rows that NAVIGATE to `/trainer/clients/:clientId/templates/:assignmentId` (assigning navigates there with `?share=1` to auto-open the reference picker), Client Activity (recent entries deep-link to the detail page's Data Entries tab), and chat. Only the Account & Access dialog remains here.
