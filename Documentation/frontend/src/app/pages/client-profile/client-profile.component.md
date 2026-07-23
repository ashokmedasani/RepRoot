# frontend/src/app/pages/clients/client-profile/client-profile.component.ts

## What this file does

The client portal home: trainer-style left navigation with My Details, Trainer, and Templates.

## Why this file exists

Clients record their check-ins here; submissions flow to the trainer's client profile view, and the trainer's curated references stream in-app.

## Page or module

Client portal at `/client/profile`.

## Important functions/classes/components

- `selectTemplate(template)`: selects one assigned template for the two-column template workspace.
- `setTab('templates')`: expands/collapses nested template navigation.
- `draftFor(template)`: per-template entry draft (date/time default to now, all fields optional, plus a feelings note).
- `submitEntry`: creates or updates a permitted template entry.
- `numericStatsFor(template)` / `templateCharts(template)`: build Overview KPIs and charts only from submitted data.
- `handleEntryImage`: downscales photos to about 800px JPEG data URLs before submission.
- `progressFor(template)`: exposes trainer-shared progress records inside the selected template Progress tab.
- `registrationAnswers`: the client's submitted registration details, with the existing edit-request flow.
- Trainer/Profile and Trainer/Chat are separate internal tabs.

## Data flow

Loads `getMe`, `getTemplates`, `getEntries`, and read-only `getProgress` when a portal token exists; sign-out clears the token and session record.

## Connected files

- `frontend/src/app/core/api/client-api.service.ts`
- `frontend/src/app/shared/chat-panel/chat-panel.component.ts`

## Update

Templates now live as nested left-nav items under Templates. The main content uses four internal tabs: Overview, References, Data Entry, and Progress. Overview excludes references/forms/recent entries and only shows KPIs or graphs when submitted data exists.

## Update 2

Desktop navigation now mirrors the trainer portal more closely with a persistent left sidebar. Template selector cards were removed from the main content area. Testing performed: `npm run build`.
