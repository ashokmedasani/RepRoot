# backend/admin_portal/permissions.py

Resolves effective permissions from role grants plus staff-specific allow/deny overrides. `HasAdminPermission` requires an authenticated active internal staff profile and the view's exact permission code.
