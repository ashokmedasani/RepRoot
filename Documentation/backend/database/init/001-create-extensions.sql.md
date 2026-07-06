# backend/database/init/001-create-extensions.sql

## What this file does

Creates PostgreSQL extensions during Docker database initialization.

## Why this file exists

Database initialization scripts allow local PostgreSQL to be prepared consistently.

## Page or module

Backend database setup.

## Important functions/classes/components

- `citext` extension.

## Data flow

Docker runs this SQL file when initializing a fresh PostgreSQL data volume.

## Connected files

- `docker-compose.yml`

## Business logic

None currently. The extension is available for future case-insensitive text fields if approved.

## Assumptions made

The script runs only during first-time database container initialization.

## Future improvement notes

Add additional PostgreSQL extensions only when a feature requires them.
