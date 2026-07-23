# backend/accounts/client_auth.py

## What this file does

Implements token authentication for client portal users (ClientAccess records), which are not Django auth users.

## Why this file exists

Clients need real authenticated requests (tracking entries, chat, profile), but DRF's TokenAuthentication only works for Django users. This module issues opaque tokens per client and authenticates `Authorization: ClientToken <key>` headers.

## Page or module

Backend accounts module, client portal authentication.

## Important functions/classes/components

- `issue_client_token(client_access)`: creates or returns the client's `ClientAuthToken`.
- `ClientTokenAuthentication`: DRF authentication class; sets `request.auth` to the active `ClientAccess`.
- `IsAuthenticatedClient`: permission that requires `request.auth` to be a `ClientAccess`.

## Data flow

`ClientLoginView` issues the token on successful login. The Angular client portal stores it in sessionStorage and sends it on every `/client/...` request. Inactive clients are rejected at authentication time.

## Connected files

- `backend/accounts/models.py` (`ClientAuthToken`)
- `backend/accounts/views.py` (client portal views)
- `frontend/src/app/core/api/client-api.service.ts`
