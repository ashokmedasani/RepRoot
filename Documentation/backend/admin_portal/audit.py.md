# backend/admin_portal/audit.py

Creates immutable administrative audit records with correlation IDs and safe identity snapshots.

- Trainer target: `username · TRN-reference`
- Client target: `trainer_username:CL-reference`
- Staff target: `STF-reference · staff name`

Foreign keys support current relationships; snapshots preserve historical readability after names change.
