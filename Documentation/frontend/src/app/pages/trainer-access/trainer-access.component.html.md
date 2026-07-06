# frontend/src/app/pages/trainer-access/trainer-access.component.html

## What this file does

Renders Login and Signup choice boxes for trainers.

## Why this file exists

The trainer card on Client Management should lead to a separate page where login and signup are visually separated.

## Page or module

Trainer Access page.

## Important functions/classes/components

- Login choice card linking to `/trainer/login`.
- Signup choice card linking to `/trainer/signup`.
- Top-right Back link to `/portal`.

## Data flow

No business data flows through this template. It uses Angular routing links.

## Connected files

- `frontend/src/app/pages/trainer-access/trainer-access.component.ts`
- `frontend/src/app/pages/trainer-access/trainer-access.component.scss`

## Business logic

None.

## Assumptions made

Separate rounded choice boxes make the next action clearer.

## Future improvement notes

Add client-specific access choices when client login is approved.
