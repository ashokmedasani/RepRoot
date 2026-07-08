# frontend/src/app/pages/trainer-group-create/trainer-group-create.component.ts

## What this file does

Controls the guided group creation page at `/trainer/groups/create`.

## Why this file exists

After creating Form 1, trainers need a focused step to create at least one group before defining the group client creation form.

## Important behavior

- Verifies a lead form exists before continuing.
- Suggests the next group name.
- Creates a group through `FormsGroupsApiService`.
- Redirects to the group client form creation route.

## Connected files

- `trainer-group-create.component.html`
- `trainer-group-create.component.scss`
