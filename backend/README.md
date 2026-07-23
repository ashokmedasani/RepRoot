# Backend Setup

The backend is a Django and Django REST Framework project configured for PostgreSQL.

## Local Setup

1. Create and activate the virtual environment:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
```

2. Install dependencies:

```powershell
python -m pip install -r requirements.txt
```

3. Make sure PostgreSQL is running locally.

Check available local database tooling:

```powershell
.\scripts\check-database-prereqs.ps1
```

Recommended Docker path from the project root:

```powershell
docker compose up -d postgres
```

Direct PostgreSQL install path:

```sql
CREATE DATABASE professional_platform;
```

You can also run the SQL from `backend/database/create_database.sql` using your preferred PostgreSQL client.

The default local credentials are:

- Database: `professional_platform`
- User: `postgres`
- Password: `postgres`
- Host: `localhost`
- Port: `5432`

Override these values with environment variables when needed.

4. Apply migrations:

```powershell
python manage.py migrate
```

Or from the backend folder:

```powershell
.\scripts\migrate.ps1
```

5. Run the backend:

```powershell
python manage.py runserver 127.0.0.1:8000
```

Or:

```powershell
.\scripts\run-server.ps1
```

## Email OTP Delivery

By default, local development prints OTP emails in the Django backend terminal. To deliver OTPs to a real inbox, set SMTP environment variables before starting Django:

```powershell
$env:EMAIL_HOST="smtp.gmail.com"
$env:EMAIL_PORT="587"
$env:EMAIL_HOST_USER="your-email@gmail.com"
$env:EMAIL_HOST_PASSWORD="your-app-password"
$env:EMAIL_USE_TLS="True"
$env:DEFAULT_FROM_EMAIL="RepRoot Studio <your-email@gmail.com>"
python manage.py runserver 127.0.0.1:8000
```

For Gmail, use a Google App Password instead of your normal account password. In Render, add the same email variables on the backend service environment settings.

## Current API Endpoints

- `GET /api/health/`
- `POST /api/accounts/professional/check-username/`
- `POST /api/accounts/professional/signup/`
- `POST /api/accounts/professional/login/`

Professional signup and login are connected to Django auth, DRF token auth, and the `professional_profiles` table.
