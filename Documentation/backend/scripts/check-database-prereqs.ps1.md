# backend/scripts/check-database-prereqs.ps1

## What this file does

Checks whether Docker, `psql`, or a local PostgreSQL server binary is available.

## Why this file exists

The backend requires PostgreSQL before migrations and trainer account creation can work.

## Page or module

Backend developer tooling.

## Important functions/classes/components

None.

## Data flow

No product data flows through this script.

## Connected files

- `docker-compose.yml`
- `backend/scripts/migrate.ps1`
- `backend/config/settings.py`

## Business logic

None.

## Assumptions made

Developers may use either Docker Desktop or a direct PostgreSQL installation.

## Future improvement notes

Add automated service startup once a single database installation path is chosen.
