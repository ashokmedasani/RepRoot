# frontend/src/app/pages/access-entry-placeholder/access-entry-placeholder.component.ts

## What this file does

Defines the Client Management access selection page.

## Why this file exists

The Page 1 `Let's Start` button routes here so users can choose whether they are a trainer or client before moving into separate login/signup pages.

## Page or module

Page 2: Client Management access selection.

## Important functions/classes/components

- `AccessEntryPlaceholderComponent`: standalone route component that manages access card selection state.

## Data flow

Only selection state flows through this component. Login and signup data now live on separate pages.

## Connected files

- `frontend/src/app/app.routes.ts`
- `frontend/src/app/pages/access-entry-placeholder/access-entry-placeholder.component.html`
- `frontend/src/app/pages/access-entry-placeholder/access-entry-placeholder.component.scss`
- `frontend/src/app/pages/trainer-access/trainer-access.component.ts`

## Business logic

Trainer card routes directly to Trainer Login. Client Portal remains future scope.

## Assumptions

Trainer login and signup happen on separate routes.

## Future improvement notes

Rename the component away from placeholder terminology in a future cleanup.
