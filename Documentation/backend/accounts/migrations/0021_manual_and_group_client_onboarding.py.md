# backend/accounts/migrations/0021_manual_and_group_client_onboarding.py

## 2026-07-13 responsibilities

Creates the group-registration submission schema, public registration slugs, manual/group onboarding sources, onboarding method, and internal client reference IDs, including data backfill.

## Integration

This file participates in the targeted workflow refinements documented in `Documentation/CHANGELOG-refinements-2026-07-13.md`. Existing theme tokens and business rules remain authoritative.

## Verification

Covered by the Django system check, migration drift check, and accounts API regression tests.

