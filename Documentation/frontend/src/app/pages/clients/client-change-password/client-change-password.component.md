# frontend/src/app/pages/clients/client-change-password/client-change-password.component.ts

## 2026-07-15 UI, workflow, and bug fixes

Stores the rotated token returned by the backend before continuing to the dashboard, fixing the post-change 'Invalid token' failure.

## 2026-07-13 responsibilities

Completes the required first-login password-change flow and returns the client to the Client Dashboard.

## Integration

This file participates in the targeted workflow refinements documented in `Documentation/CHANGELOG-refinements-2026-07-13.md`. Existing theme tokens and business rules remain authoritative.

## Verification

Covered by the successful Angular production build and relevant backend API regression tests.

