# frontend/src/app/pages/trainer-group-users/trainer-group-users.component.ts

## What this file does

Controls the group users page at `/trainer/groups/:groupId/users`.

## Why this file exists

The Forms & Groups dashboard links to a separate page for viewing users created under a group instead of embedding approved users inside the group card.

## Important behavior

- Loads active users for the selected group.
- Displays the group name and active user count.
- Shows API errors without leaving the page blank.

## Connected files

- `trainer-group-users.component.html`
- `trainer-group-users.component.scss`
- `frontend/src/app/core/api/forms-groups-api.service.ts`

## Update: trainer-level templates

The Tracking Templates tab now lists the trainer's shared templates from `TemplatesApiService` (read-only preview with a Manage Templates link) instead of per-group localStorage. Shared helpers `initialsFor` and `formatApiError` replaced the local copies, and the offline fallback group was removed.

## Update 2

The Tracking Templates tab was removed from the group workspace entirely - templates live only in the dedicated `/trainer/templates` section. The overview now shows a pending-invites card instead of a template count.

## Update 3

Group navigation is now Overview, Approved Users, Client Registration Form, and Settings. Overview keeps only summary cards plus a full-width Recent Approved Users strip limited to five active clients.

## Update 4

Settings now uses one expandable Group Settings card containing only editable group details. Version 1 hides access/permission rules until a shared rules system exists. Testing performed: `npm run build`.
