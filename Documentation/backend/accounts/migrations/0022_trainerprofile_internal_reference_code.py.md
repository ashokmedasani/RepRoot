# backend/accounts/migrations/0022_trainerprofile_internal_reference_code.py

Adds the immutable trainer internal reference safely in three steps: nullable field, unique per-row backfill, then unique/not-null enforcement. Existing production trainers receive different `TRN-…` values.
