# Render Deployment

This project deploys as two Render services:

- `fitness-app-backend`: Django REST API
- `fitness-app-frontend`: Angular static site

## 1. Push the branch

Push this repository branch to GitHub, then create the services from the Render dashboard or from `render.yaml`.

## 2. Create the PostgreSQL database

Use a Render PostgreSQL database or any external PostgreSQL provider. Copy its external/internal database URL.

Set this backend environment variable:

```text
DATABASE_URL=postgresql://USER:PASSWORD@HOST:PORT/DATABASE
```

When `DATABASE_URL` is present, the backend uses it automatically. On every backend startup, `backend/scripts/render_start.sh` runs:

```bash
python manage.py migrate --noinput
python manage.py collectstatic --noinput
gunicorn config.wsgi:application --bind "0.0.0.0:${PORT:-8000}"
```

That means schema setup and future migrations are applied automatically after you add the external database link.

## 3. Backend environment variables

Required:

```text
DJANGO_DEBUG=False
DJANGO_SECRET_KEY=<generate a strong secret>
DJANGO_ALLOWED_HOSTS=<your-backend>.onrender.com
DATABASE_URL=<external postgres database url>
CORS_ALLOWED_ORIGINS=https://<your-frontend>.onrender.com
CSRF_TRUSTED_ORIGINS=https://<your-frontend>.onrender.com
```

Production startup intentionally fails if SMTP is not configured. Set `EMAIL_HOST`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, and `DEFAULT_FROM_EMAIL` before the first deployment so OTP and client-credential messages are delivered securely instead of printed to logs.

Also configure:

```text
CACHE_URL=redis://...                 # shared OTP, throttle, and verification state
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_STORAGE_BUCKET_NAME=...
AWS_S3_REGION_NAME=...
AWS_S3_ENDPOINT_URL=...              # only for non-AWS S3-compatible providers
```

Durable object storage is required for deployed profile and reference uploads because a web-service filesystem is not durable. Redis is strongly recommended before running more than one API process.

## 4. Frontend API configuration

Set this frontend environment variable in Render:

```text
RENDER_API_BASE_URL=https://<your-backend>.onrender.com
```

The frontend Render build command runs `npm run build:render`, which writes `frontend/public/app-config.js` before Angular builds:

```javascript
window.APP_CONFIG = {
  apiBaseUrl: 'https://<your-backend>.onrender.com'
};
```

For local development, leave `apiBaseUrl` blank. The Angular app falls back to:

```text
http://127.0.0.1:8000/api/accounts
```

## 5. Render commands

Backend:

```text
Root Directory: backend
Build Command: pip install -r requirements.txt
Start Command: bash scripts/render_start.sh
Health Check Path: /api/health/
```

Frontend:

```text
Root Directory: frontend
Build Command: npm ci && npm run build:render
Publish Directory: dist/professional-management-platform/browser
Rewrite Rule: /* -> /index.html
```

## 6. Verify deployment

Open these URLs after deployment:

```text
https://<your-backend>.onrender.com/api/health/
https://<your-frontend>.onrender.com/
```

The health endpoint should return:

```json
{"status": "ok"}
```

Before directing real users to the deployment, also run `python manage.py check --deploy`, `python manage.py migrate --check`, the backend test suite, the Angular production build, and both Python and npm vulnerability audits.
