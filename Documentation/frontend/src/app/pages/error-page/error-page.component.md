# frontend/src/app/pages/error-page/error-page.component.ts

## Purpose

Controls the shared error and not-found experience.

## User workflow

- Reads safe error state supplied by routing or the centralized error service.
- `Try Again` reloads only a validated internal application URL.
- `Go to Home` chooses Trainer Dashboard, Client Dashboard, or the public landing page based on the current session.
- `Go Back` returns through browser history with a safe-home fallback.

The page never displays exception text, API payloads, credentials, or stack traces.
