# backend/README.md

## What this file does

Documents how to set up, migrate, and run the Django backend locally.

## Why this file exists

The backend now has real dependencies, PostgreSQL settings, migrations, and API endpoints that need clear local run instructions.

## Page or module

Backend project setup.

## Important functions/classes/components

None.

## Data flow

No application data flows through this documentation file.

## Connected files

- `backend/requirements.txt`
- `backend/manage.py`
- `backend/config/settings.py`
- `backend/accounts`
- `backend/database/create_database.sql`
- `docker-compose.yml`
- `backend/scripts/migrate.ps1`
- `backend/scripts/run-server.ps1`
- `backend/scripts/check-database-prereqs.ps1`

## Business logic

Documents the currently approved trainer username check, signup, and login endpoints.

## Assumptions made

PostgreSQL must be installed and running locally before migrations can be applied. The recommended setup is `docker compose up -d postgres`; direct PostgreSQL installs can use `backend/database/create_database.sql`.

## Future improvement notes

Add Docker or managed database setup instructions if that path is approved.
