# frontend/src/app/pages/trainer/trainer-client-template/trainer-client-template.component.ts

## What this file does

Standalone Template Detail page at `/trainer/clients/:clientId/templates/:assignmentId` - opened from a client profile's assigned-template rows. Header actions: Back, Share References, Start New Entry (trainer records for the client). Tabs: Overview (shared reference cards, template notes, structure, today + 7-day trend table), Data Entries (per-template table with edit dialog), Progress (30-day consistency, numeric trends, client notes).

## Why this file exists

The reference design treats the client profile and the template detail as two separate screens; this page carries all per-assignment functionality (previously an inline panel on the profile).

## Connected files

- `frontend/src/app/pages/trainer/trainer-client-profile/trainer-client-profile.component.ts` (navigates here)
- `frontend/src/app/core/api/templates-api.service.ts`, `references-api.service.ts`
