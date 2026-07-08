# frontend/src/app/pages/clients/client-change-password/client-change-password.component.ts

## What this file does

Forced password-change page for clients logging in with a temporary password.

## Why this file exists

Trainer-issued temporary passwords must be replaced by a client-owned password; the backend clears `must_change_password` on success.

## Page or module

Client portal at `/client/change-password`.

## Important functions/classes/components

- `changePassword`: validates match, calls `ClientApiService.changePassword`, refreshes the stored client record, and enters the portal.
- Prompts login when no portal token is present.

## Connected files

- `frontend/src/app/core/api/client-api.service.ts`
- `frontend/src/app/pages/clients/client-login/client-login.component.ts`
