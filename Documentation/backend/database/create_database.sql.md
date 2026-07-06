# backend/database/create_database.sql

## What this file does

Creates the local PostgreSQL database used by the Django backend.

## Why this file exists

The project requires PostgreSQL, and database creation should be explicit and repeatable.

## Page or module

Backend database setup.

## Important functions/classes/components

None.

## Data flow

Django connects to the `trainer_platform` database after it exists and migrations are applied.

## Connected files

- `backend/config/settings.py`
- `backend/accounts/migrations/0001_initial.py`

## Business logic

None. This file only creates the database container for application tables.

## Assumptions made

The local PostgreSQL user has permission to create databases.

## Future improvement notes

Replace or supplement this with Docker/database provisioning if approved.
