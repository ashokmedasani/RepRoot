# src/app/app.component.ts

## What this file does

Defines the Angular root component and initializes the active theme when the app starts.

## Why this file exists

Every Angular application needs a root component to host routed pages.

## Page or module

Global frontend application shell.

## Important classes

- `AppComponent`: root standalone component.

## Data flow

The component initializes theme state through `ThemeService`. Page rendering flows through `RouterOutlet`.

## Connected files

- `frontend/src/app/app.component.html`
- `frontend/src/app/app.component.scss`
- `frontend/src/app/app.routes.ts`
- `frontend/src/app/core/theme/theme.service.ts`

## Business logic

None. The component only performs application shell setup.

## Assumptions

Theme initialization belongs at the app shell level so every page receives the same theme context.

## Future improvements

Add global layout concerns only after authenticated pages and navigation are approved.
