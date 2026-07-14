# frontend/src/app/core/guards/portal-auth.guards.ts

## Purpose

Protects trainer and client portal routes before components load. Trainer routes require the trainer token in local storage; client routes require the client token in session storage. Missing access redirects to the matching login page.

## Verification

Covered by the successful Angular production build and authenticated route preview on port 4400.
