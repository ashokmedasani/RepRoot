# src/app/app.component.html

## 2026-07-13 targeted refinement

Hosts the single global confirmation dialog outlet used throughout the application.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Hosts the Angular router outlet where active pages render.

## Why this file exists

The app needs a single shell template that can display Page 1 now and future approved pages later.

## Page or module

Global frontend application shell.

## Important elements

- `router-outlet`: renders the active route component.

## Data flow

No business data flows through this template. Angular routing decides which page appears.

## Connected files

- `frontend/src/app/app.component.ts`
- `frontend/src/app/app.routes.ts`

## Business logic

None.

## Assumptions

The landing page owns its own layout, so the root template stays minimal.

## Future improvements

Introduce a shared authenticated layout only after authenticated pages are approved.
