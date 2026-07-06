# backend/accounts/migrations/0004_trainerprofile_setup_portfolio.py

## What this file does

Adds trainer profile setup and Profile / Portfolio fields to the `trainer_profiles` table.

## Why this file exists

The database needs persistent storage for first-login profile setup, media uploads, professional details, certifications, and public portfolio links.

## Page or module

Backend accounts module for trainer profile setup and Profile / Portfolio.

## Important changes

- Adds `profile_setup_completed`.
- Adds profile, certification, transformation, and training upload fields.
- Adds professional headline, about me, trainer type, experience, specializations, training style, languages, certification metadata, and public links.

## Data flow

The migration updates PostgreSQL schema. `TrainerProfileSerializer` reads and writes these fields after migration.

## Business logic

The completion flag controls whether trainers are routed to `/trainer/profile-setup` or `/trainer/profile`.

## Connected files

- `backend/accounts/models.py`
- `backend/accounts/serializers.py`

## Future improvement notes

Normalize repeated portfolio data into separate tables when multiple entries are required.
