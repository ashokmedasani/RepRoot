# Local Setup and Testing

1. Run `python manage.py migrate`.
2. Create staff with `python manage.py create_admin_staff ...` using a strong password.
3. Open `/admin-portal/login`.
4. Run backend verification with `python manage.py test admin_portal accounts`.
5. Run frontend verification with `npm run build`.

No temporary test staff should be retained after manual QA.
