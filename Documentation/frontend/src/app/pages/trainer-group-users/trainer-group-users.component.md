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
