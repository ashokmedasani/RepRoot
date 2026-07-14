# backend/accounts/data_usage.py

## 2026-07-13 stable quota gauge refinement

Returns logical database bytes, uploaded-file bytes, total bytes, the configured storage quota, and usage percentage. Authentication timestamps are excluded, and the configurable 15-minute cache keeps normal navigation from changing the indicator.

The quota comes from `COACHFLOW_PLAN_LIMITS['trainer_storage_bytes']`; no quota is embedded in frontend code.

## Purpose

Calculates a trainer-scoped storage estimate containing trainer-owned database records, client content, embedded profile images, and uploaded profile/reference files.

## Ownership and safety

Every queryset is filtered through the authenticated trainer. File-size lookups fail safely when an upload is missing or an object-storage provider cannot return its size.

## Verification

Covered by the trainer data-usage API regression test and the live port 4400 sidebar preview.
