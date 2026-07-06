# backend/accounts/models.py

## What this file does

Defines database models for trainer account profile data.

## Why this file exists

Django's built-in `User` model stores authentication and identity fields. `TrainerProfile` stores trainer-specific setup, profile, and portfolio data without mixing it into the auth table.

## Page or module

Backend accounts module for trainer signup, login, profile setup, and Profile / Portfolio.

## Important functions/classes/components

- `TrainerProfile`: one-to-one profile linked to Django's user model.
- `profile_setup_completed`: controls whether a trainer must complete `/trainer/profile-setup`.
- File fields: store profile photo, certification upload, transformation photo, and training photo.

## Data flow

Trainer signup creates a Django `User` and linked `TrainerProfile`. Profile setup and Profile / Portfolio APIs update the same `TrainerProfile` row and update the user's first and last name through serializers.

## Connected files

- `backend/accounts/serializers.py`
- `backend/accounts/views.py`
- `backend/accounts/admin.py`
- `backend/accounts/migrations/0004_trainerprofile_setup_portfolio.py`

## Business logic

New trainer profiles start as incomplete. Saving required setup fields marks `profile_setup_completed` as true.

## Assumptions made

The first version stores one certification and one upload per media category. Multi-item galleries can be added later with related tables.

## Future improvement notes

Move portfolio media and certifications into separate models when approval, ordering, and multiple uploads are required.
