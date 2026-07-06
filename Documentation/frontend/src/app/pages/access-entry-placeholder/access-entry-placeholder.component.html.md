# frontend/src/app/pages/access-entry-placeholder/access-entry-placeholder.component.html

## What this file does

Renders the Page 2 Client Management access selection.

## Why this file exists

The landing page start button opens a real design page where the user can choose Trainer or Client Portal.

## Page or module

Page 2: Trainer Login / Signup and Client Login Page.

## Important functions/classes/components

- Client Management header.
- Trainer and Client Portal selection cards.
- Rounded Trainer card linking directly to `/trainer/login`.
- Rounded Client Portal card.
- Top-right Back link.

## Data flow

The template uses Angular routing for the Trainer card and Back link.

## Connected files

- `frontend/src/app/pages/access-entry-placeholder/access-entry-placeholder.component.ts`
- `frontend/src/app/pages/access-entry-placeholder/access-entry-placeholder.component.scss`

## Business logic

Trainer card routes directly to Trainer Login. Client Portal shows a future-scope notice.

## Assumptions

The page does not send trainer signup/login data directly.

## Future improvement notes

Add client login route after that workflow is approved.
