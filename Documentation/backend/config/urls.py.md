# backend/config/urls.py

## 2026-07-13 Admin Portal API namespace

Mounts protected internal APIs beneath `/api/admin/`. These endpoints do not share trainer/client portal routes.

## What this file does

Defines root URL routing for the Django project.

## Why this file exists

This is the backend's top-level router.

## Page or module

Backend project configuration.

## Important routes

- `/admin/`
- `/api/health/`
- `/api/accounts/`
- `/media/` in local debug mode

## Data flow

Account requests are delegated to `backend/accounts/urls.py`. Local upload URLs are served from `MEDIA_ROOT` while `DEBUG` is true.

## Business logic

No direct business logic lives here. The media route supports local profile and portfolio upload previews.

## Connected files

- `backend/accounts/urls.py`
- `backend/config/settings.py`

## Future improvement notes

Use production-grade static/media hosting outside Django debug serving.
