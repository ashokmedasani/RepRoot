# docker-compose.yml

## What this file does

Defines the local PostgreSQL service for development.

## Why this file exists

The application requires PostgreSQL, and Docker Compose gives the project a repeatable local database setup.

## Page or module

Project-level local infrastructure.

## Important functions/classes/components

- `postgres`: PostgreSQL 16 container.
- `postgres_data`: persistent database volume.
- Health check using `pg_isready`.

## Data flow

Django connects to PostgreSQL through `localhost:5432` using the credentials defined in this file.

## Connected files

- `backend/config/settings.py`
- `backend/database/init/001-create-extensions.sql`
- `backend/scripts/migrate.ps1`

## Business logic

None. This file provisions infrastructure only.

## Assumptions made

Docker Desktop or Docker Engine is installed and supports Compose v2.

## Future improvement notes

Add separate compose profiles for production-like services only when deployment testing begins.
