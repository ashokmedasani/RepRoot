# frontend/src/app/shared/chat-panel/chat-panel.component.ts

## What this file does

Reusable trainer-client chat panel with message list, composer, and five-second polling while visible.

## Why this file exists

Both the trainer client profile and the client portal need the same chat UI against the same backend thread; one shared component replaces the two localStorage stubs.

## Page or module

Shared frontend components.

## Important functions/classes/components

- Inputs: `mode` (`trainer` or `client`), `clientId` (trainer mode), `counterpartName`, `description`.
- `sendMessage` posts through `ChatApiService` for the active mode.
- Poll timer fetches messages `?after=<last id>` and appends; cleared on destroy.

## Data flow

Messages come from the backend `ChatMessage` table, so both sides finally see the same conversation.

## Connected files

- `frontend/src/app/core/api/chat-api.service.ts`
- `frontend/src/app/pages/trainer/trainer-client-profile/trainer-client-profile.component.html`
- `frontend/src/app/pages/clients/client-profile/client-profile.component.html`
