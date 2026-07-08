# frontend/src/app/pages/clients/client-profile/client-profile.component.ts

## What this file does

The client portal home: assigned templates to fill in daily, personal details, trainer resources, and chat - organized in tabs.

## Why this file exists

Clients record their check-ins here; submissions flow to the trainer's client profile view, and the trainer's curated references stream in-app.

## Page or module

Client portal at `/client/profile`.

## Important functions/classes/components

- `draftFor(template)`: per-template entry draft (date defaults to today, all fields optional, plus a feelings note).
- `submitEntry`: upserts by template and date - resubmitting the same day updates the entry.
- `handleEntryImage`: downscales photos to about 800px JPEG data URLs before submission.
- `resources`: deduplicated references across assigned templates; YouTube links stream via sanitized embeds.
- `registrationAnswers` / `leadAnswers`: the client's submitted forms, read-only.
- Chat tab renders the shared chat panel in client mode.

## Data flow

Loads `getMe`, `getTemplates`, and `getEntries` when a portal token exists; sign-out clears the token and session record.

## Connected files

- `frontend/src/app/core/api/client-api.service.ts`
- `frontend/src/app/shared/chat-panel/chat-panel.component.ts`

## Update

Resources now come from the references the trainer shared on each assignment (not from the template definition); the portal behavior is otherwise unchanged.
