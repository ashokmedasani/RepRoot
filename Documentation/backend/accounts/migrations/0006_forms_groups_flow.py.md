# backend/accounts/migrations/0006_forms_groups_flow.py

## What this file does

Creates database tables for the Forms & Groups setup flow.

## Why this file exists

The trainer needs persistent Form 1 setup, groups, group-specific client registration forms, public lead submissions, and converted client access records.

## Page or module

Backend accounts module, Forms & Groups feature.

## Important models created

- `TrainerLeadForm`
- `TrainerGroup`
- `ClientRegistrationForm`
- `LeadSubmission`
- `ClientAccess`

## Business logic

The migration stores one lead form per trainer, one registration form per group, and trainer-scoped uniqueness for client email and username.

## Connected files

- `backend/accounts/models.py`
- `backend/accounts/serializers.py`
- `backend/accounts/views.py`
