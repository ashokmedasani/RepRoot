# backend/config/settings.py

## 2026-07-13 Admin Portal

Registers the isolated `admin_portal` Django application. Trainer and client authentication applications remain unchanged.

## 2026-07-13 trainer storage configuration

Adds configurable `COACHFLOW_TRAINER_STORAGE_LIMIT_BYTES` with a 100 MB Version 1 default and `COACHFLOW_DATA_USAGE_CACHE_SECONDS` with a 15-minute default. Both can change by environment without UI edits.

## 2026-07-13 targeted refinement

Defines configurable Version 1 limits for references, categories, and subcategories so later plans can raise or remove limits.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

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

Production refuses the development secret and console email backend. Durable S3-compatible media, Redis-backed cache, HTTPS/HSTS/cookie protections, response hardening, and scoped API throttle rates are environment-configurable. Local development retains filesystem media and local-memory cache defaults.
