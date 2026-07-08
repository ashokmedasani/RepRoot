# frontend/src/app/pages/trainer-forms-groups/trainer-forms-groups.component.ts

## What this file does

Controls the trainer Forms & Groups dashboard page.

## Why this file exists

Trainers need a clean dashboard after setup, plus an empty state that directs them into the guided setup flow when no lead form exists.

## Page or module

Trainer Forms & Groups page.

## Important functions/classes/components

- Loads setup status from `FormsGroupsApiService`.
- Shows the no-form empty state with a Create Form action.
- Displays the screenshot-style Form 1 card with link copy, request stats, field summary, and edit route.
- Displays pending, approved/converted, and deleted submissions with a monthly filter.
- Displays compact group rows with client creation form status, View users, and edit form actions.
- Starts and submits the Create Client Access flow.

## Business logic

This component checks only Forms & Groups state. It does not check or redirect based on trainer profile setup. Form/group/client-form creation is handled by separate guided routes.

## Connected files

- `trainer-forms-groups.component.html`
- `trainer-forms-groups.component.scss`
- `frontend/src/app/core/api/forms-groups-api.service.ts`
