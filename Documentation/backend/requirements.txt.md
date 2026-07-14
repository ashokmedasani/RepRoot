# backend/requirements.txt

## What this file does

Defines the Python packages required for the Django backend.

## Why this file exists

The backend needs a separate dependency manifest from the Angular frontend so both stacks remain cleanly separated.

## Page or module

Backend project setup.

## Important dependencies

- `Django`: backend framework.
- `djangorestframework`: API framework.
- `django-cors-headers`: local frontend-backend CORS support.
- `psycopg[binary]`: PostgreSQL database adapter.

## Data flow

No application data flows through this file.

## Connected files

- `backend/manage.py`
- `backend/config/settings.py`

## Business logic

None.

## Assumptions

PostgreSQL is the confirmed database for Version 1.

## Future improvement notes

Pin exact versions after the first stable development environment is approved.

## 2026-07-13 production audit

Adds `django-storages[s3]` for durable production uploads and `redis` for a shared cache/throttle backend. Dependency auditing reported no known Python package vulnerabilities.
