# Admin Portal Overview — Phase 1

The Admin Portal is an isolated internal application surface with its own `/admin-portal/*` routes, `/api/admin/*` APIs, session token, page shell, role/permission checks, and audit trail. Trainers and clients cannot use these credentials or endpoints.

Implemented in this checkpoint: staff login, RBAC foundation, aggregate Dashboard, separate Finance page, immutable Audit Logs, management-command staff creation, migrations, and tests. Trainer/client search and account actions remain Phase 2 per the requested checkpoint order.
