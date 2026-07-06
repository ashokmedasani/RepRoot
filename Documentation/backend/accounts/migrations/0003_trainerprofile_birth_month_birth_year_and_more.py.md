# backend/accounts/migrations/0003_trainerprofile_birth_month_birth_year_and_more.py

## What this file does

Adds birth month and birth year fields to trainer profiles and allows country to be blank.

## Why this file exists

The approved signup form now asks for age information using only month and year, and no longer asks for country.

## Page or module

Backend accounts database migrations.

## Important functions/classes/components

- Adds `birth_month`.
- Adds `birth_year`.
- Alters `country` to allow blank values.

## Data flow

Django applies this migration to PostgreSQL during `python manage.py migrate`.

## Connected files

- `backend/accounts/models.py`
- `backend/accounts/serializers.py`

## Business logic

Trainer signup stores birth month and birth year for the trainer profile.

## Assumptions made

Only month and year are required for this design step; exact date of birth is intentionally not collected.

## Future improvement notes

Clarify whether these fields represent birth date or age period before production.
