# backend/accounts/migrations/0001_initial.py

## What this file does

Creates the `trainer_profiles` table.

## Why this file exists

Trainer profile fields need a normalized relational table linked to Django's auth user table.

## Page or module

Backend accounts database migrations.

## Important functions/classes/components

- `CreateModel TrainerProfile`: creates trainer profile storage.

## Data flow

Django migrations apply this schema to PostgreSQL during `python manage.py migrate`.

## Connected files

- `backend/accounts/models.py`

## Business logic

Each trainer profile links one-to-one with a user and stores state, country, terms acceptance, and timestamps.

## Assumptions made

Django's built-in auth migrations will create the user table before this migration runs.

## Future improvement notes

Add new migrations as approved trainer profile fields are introduced.
