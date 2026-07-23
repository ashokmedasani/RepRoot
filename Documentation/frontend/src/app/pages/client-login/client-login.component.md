# frontend/src/app/pages/clients/client-login/client-login.component.ts

## What this file does

Client portal login form.

## Why this file exists

Clients log in with the username and password their trainer created (or a temporary password after a reset).

## Page or module

Client portal at `/client/login`.

## Important functions/classes/components

- `verifyClientLogin`: calls `ClientApiService.login`, stores the portal token (`client-auth-token`) and client record in sessionStorage.
- Redirects to `/client/change-password` when `must_change_password` is set, otherwise to `/client/profile`.
- Uses the shared `formatApiError` helper.

## Connected files

- `frontend/src/app/core/api/client-api.service.ts`
- `frontend/src/app/pages/clients/client-change-password/client-change-password.component.ts`
