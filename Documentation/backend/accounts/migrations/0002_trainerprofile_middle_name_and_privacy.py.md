# backend/accounts/migrations/0002_trainerprofile_middle_name_and_privacy.py

## What this file does

Adds `middle_name` and `privacy_policy_accepted` fields to trainer profiles.

## Why this file exists

Trainer signup now includes optional middle name and mandatory privacy policy acceptance.

## Page or module

Backend accounts database migrations.

## Important functions/classes/components

- Adds `middle_name`.
- Adds `privacy_policy_accepted`.

## Data flow

Django applies this migration to PostgreSQL during `python manage.py migrate`.

## Connected files

- `backend/accounts/models.py`
- `backend/accounts/serializers.py`

## Business logic

Privacy policy acceptance is tracked for each trainer profile.

## Assumptions made

Existing trainer records receive blank middle name and `False` privacy policy acceptance until updated.

## Future improvement notes

Add timestamped legal acceptance records if audit requirements become stricter.
