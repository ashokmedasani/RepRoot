# backend/config/settings.py

## What this file does

Configures the Django backend project for local development.

## Why this file exists

The backend needs a clear configuration layer for installed apps, middleware, PostgreSQL, CORS, static files, media files, email, cache, and Django REST Framework.

## Page or module

Backend project configuration.

## Important settings

- `INSTALLED_APPS`: includes Django defaults, `corsheaders`, `rest_framework`, DRF token auth, and `accounts`.
- `DATABASES`: uses PostgreSQL through environment variables with local defaults.
- `MEDIA_URL` and `MEDIA_ROOT`: store local trainer profile and portfolio uploads.
- `CORS_ALLOWED_ORIGINS`: allows Angular development ports `4200` and `4300`.
- `REST_FRAMEWORK`: defaults to token authentication and authenticated API access.
- `EMAIL_BACKEND`: uses Django console email for free local OTP testing.
- `CACHES`: uses local memory cache for temporary OTP and verification token storage.

## Data flow

Environment variables flow into Django settings. Trainer profile uploads are written under `MEDIA_ROOT` during local development.

## Connected files

- `backend/manage.py`
- `backend/config/urls.py`
- `backend/accounts/views.py`
- `backend/accounts/models.py`

## Business logic

No business decisions are implemented here, but profile setup depends on media and token-auth settings.

## Assumptions

Local PostgreSQL defaults are `trainer_platform`, user `postgres`, password `postgres`, host `localhost`, and port `5432`.

## Future improvement notes

Move uploaded media to cloud object storage and move secrets into a deployment-safe environment strategy before production.
