# frontend/src/app/core/api/chat-api.service.ts

## What this file does

Typed Angular HTTP client for trainer-client chat, used by both sides of the conversation.

## Why this file exists

The previous chat was a localStorage stub that never left the browser. This service talks to the real chat endpoints so messages reach the other person.

## Page or module

Angular core API services.

## Important functions/classes/components

- `getTrainerMessages` / `sendTrainerMessage` (trainer token header).
- `getClientMessages` / `sendClientMessage` (ClientToken header from sessionStorage).
- `?after=<id>` polling parameter to fetch only new messages.

## Data flow

The shared chat panel polls every five seconds while open and appends new messages. Fetching marks the counterpart's messages as read server-side.

## Connected files

- `frontend/src/app/shared/chat-panel/chat-panel.component.ts`
- `backend/accounts/views.py`
