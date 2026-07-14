# backend/admin_portal/management/commands/create_admin_staff.py

Creates internal staff through a local management command with Django password validation and an existing seeded role. There is no public staff signup.

Example: `python manage.py create_admin_staff --username adminuser --email admin@example.com --role super-admin --password "strong-password"`
