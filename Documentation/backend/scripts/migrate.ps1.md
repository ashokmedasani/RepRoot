# backend/scripts/migrate.ps1

## What this file does

Runs Django migrations using the backend virtual environment.

## Why this file exists

Migrations should be easy to run consistently after PostgreSQL starts.

## Page or module

Backend developer tooling.

## Important functions/classes/components

None.

## Data flow

Django migration files are applied to the configured PostgreSQL database.

## Connected files

- `backend/manage.py`
- `backend/config/settings.py`
- `docker-compose.yml`

## Business logic

None.

## Assumptions made

The backend virtual environment exists at `backend/.venv`.

## Future improvement notes

Add seed data scripts only after seed data requirements are approved.
