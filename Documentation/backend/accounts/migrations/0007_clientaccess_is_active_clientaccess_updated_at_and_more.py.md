# backend/accounts/migrations/0007_clientaccess_is_active_clientaccess_updated_at_and_more.py

## What this file does

Adds aggregate-friendly lifecycle fields for future business KPI reporting.

## Why this file exists

Future admin/business dashboards need counts and rates by status, active flag, trainer, form, group, and date without exposing private user details.

## Page or module

Backend accounts module, Forms & Groups reporting readiness.

## Important fields added

- `is_active` on lead forms, groups, client registration forms, lead submissions, and client access records.
- `updated_at` on lead submissions and client access records.
- `deleted_at` on lead submissions.
- `deleted` status option on lead submissions.

## Business logic

Deleted lead submissions can now be counted as deleted records instead of disappearing from reporting. Conversion rate can be calculated from lead submission status and `converted_at`.

## Connected files

- `backend/accounts/models.py`
- `backend/accounts/views.py`
- `backend/accounts/admin.py`
