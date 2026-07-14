# backend/admin_portal/views.py

Implements protected Phase 1 endpoints for login/logout, session identity, aggregate Dashboard, Finance summary, and read-only Audit Logs. Every successful internal page access creates an audit record. Finance returns verified ledger aggregates and reports that billing is not configured instead of inventing revenue.
