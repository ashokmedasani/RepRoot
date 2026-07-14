# frontend/src/app/core/api/admin-portal-api.service.ts

Provides typed calls to the isolated `/api/admin/` namespace, keeps the Admin token in session storage, exposes effective permissions, and clears the internal session independently of trainer/client authentication.
