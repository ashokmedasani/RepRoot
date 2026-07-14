# frontend/src/app/core/errors/global-error-handler.ts

## Purpose

Replaces Angular's default uncaught-error handler with an application handler that logs the technical error for developers and shows a safe error page to the user.

Repeated navigation is guarded to prevent an error loop.

## API or database impact

None.
