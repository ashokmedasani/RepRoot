# frontend/src/app/core/errors/error.interceptor.ts

## Purpose

Provides one functional Angular HTTP interceptor for page-level failures.

## Routing rules

- Redirects status `0`, `403`, `5xx`, and GET `404` failures to the shared error page.
- Re-throws the original response so existing component cleanup and logging still run.
- Does not redirect expected `400` validation responses or `401` login-expiry responses.

## API or database impact

None.
