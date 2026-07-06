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
CREATE DATABASE trainer_platform;
```

You can also run the SQL from `backend/database/create_database.sql` using your preferred PostgreSQL client.

The default local credentials are:

- Database: `trainer_platform`
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

## Current API Endpoints

- `GET /api/health/`
- `POST /api/accounts/trainer/check-username/`
- `POST /api/accounts/trainer/signup/`
- `POST /api/accounts/trainer/login/`

Trainer signup and login are connected to Django auth, DRF token auth, and the `trainer_profiles` table.
