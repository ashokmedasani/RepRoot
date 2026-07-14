# frontend/src/app/core/errors/error-navigation.service.ts

## Purpose

Centralizes safe, user-facing error descriptions and navigation to `/error`.

## Behavior

- Network failures use an offline/service-unavailable message.
- `403` responses explain that access is restricted.
- missing GET resources use a not-found message.
- `5xx` responses use a temporary service-error message.
- unexpected frontend failures use a generic message and never expose stack traces or raw server responses.
- the route that failed is retained only as a safe internal retry destination.

Normal validation errors and login-expiry responses remain in their existing workflows.

## API or database impact

None. No migration is required.
