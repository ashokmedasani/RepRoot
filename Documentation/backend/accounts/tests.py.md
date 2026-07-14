# backend/accounts/tests.py

## 2026-07-13 storage quota coverage

The data-usage regression verifies owned client content, total byte calculation, the configurable 100 MB default quota, and a valid non-negative usage percentage.

## 2026-07-13 Client Action Center follow-up

The schedule-summary regression test now verifies pending profile-edit aggregation, activity ownership, and changed-field counting in the combined trainer activity response.

## 2026-07-13 responsibilities

Covers complete and incomplete trainer profile routing signals, manual and group client onboarding, generated references, credential email and first-login password change, schedule KPI windows, and reference usage limits.

## Integration

This file participates in the targeted workflow refinements documented in `Documentation/CHANGELOG-refinements-2026-07-13.md`. Existing theme tokens and business rules remain authoritative.

## Verification

Covered by the Django system check, migration drift check, and accounts API regression tests.

## 2026-07-13 production audit coverage

Regression coverage now also verifies legacy Additional Details normalization/removal, preservation of the complete profile-visibility contract, and client-token revocation on logout. The full suite contains eight passing tests.

The schedule regression now includes an overdue record and verifies separate overdue, future-24-hour, future-7-day, chronological queue, pending, and completed totals.

## 2026-07-13 trainer data usage

The nine-test suite now verifies that trainer-owned client content contributes to the reported total and that total bytes equal database plus uploaded-file bytes.
