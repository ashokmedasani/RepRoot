# backend/scripts/run-server.ps1

## What this file does

Starts the Django development server on `127.0.0.1:8000`.

## Why this file exists

The frontend expects the backend API at `http://127.0.0.1:8000`.

## Page or module

Backend developer tooling.

## Important functions/classes/components

None.

## Data flow

HTTP requests flow from Angular to Django REST Framework endpoints.

## Connected files

- `backend/manage.py`
- `frontend/src/app/core/api/trainer-auth-api.service.ts`

## Business logic

None.

## Assumptions made

The backend virtual environment exists at `backend/.venv`.

## Future improvement notes

Add environment-specific server scripts after deployment targets are approved.
