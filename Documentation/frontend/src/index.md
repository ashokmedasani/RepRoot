# src/index.html

## What this file does

Provides the HTML shell that hosts the Angular application.

## Why this file exists

Angular mounts the root component into the `<app-root>` element inside this document.

## Page or module

Global frontend application shell.

## Important elements

- `<base href="/">` supports Angular routing.
- `<app-root>` is the Angular mount point.
- Meta description summarizes the current product idea.

## Data flow

No app data is handled here. Angular takes control after `frontend/src/main.ts` bootstraps the app.

## Connected files

- `frontend/src/main.ts`
- `frontend/src/app/app.component.ts`

## Business logic

None.

## Assumptions

The temporary product name is used until final branding is approved.

## Future improvements

Update title, metadata, and favicon when branding is finalized.
