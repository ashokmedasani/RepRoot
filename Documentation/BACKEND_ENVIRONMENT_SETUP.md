# RepRoot Backend Environment Setup

All sensitive provider configuration belongs in the Django backend. Never add
it to Angular, Flutter, `app-config.js`, Dart defines, frontend assets, or
mobile build files. The safe reference layout is `backend/.env.example`.

For local development, manually copy the example to `backend/.env` and replace
the placeholders. For production, enter the same variables in the hosting
provider's environment/secret dashboard. Never commit `backend/.env`. Restart
or redeploy Django after changing values.

## Required before production

### Application and domains

| Variable | Secret | What to enter |
| --- | --- | --- |
| `DJANGO_SECRET_KEY` | Yes | A new long random production secret |
| `DJANGO_DEBUG` | No | `False` |
| `DJANGO_ALLOWED_HOSTS` | No | Backend hostname, such as `api.example.com` |
| `REPROOT_FRONTEND_URL` | No | Public Angular application URL |
| `CORS_ALLOWED_ORIGINS` | No | Allowed frontend origins, comma-separated |
| `CSRF_TRUSTED_ORIGINS` | No | HTTPS frontend origins, comma-separated |

Keep the secure-cookie and HSTS fields at the values shown in `.env.example`
after production HTTPS is active.

### Database and cache

| Variable | Secret | What to enter |
| --- | --- | --- |
| `DATABASE_URL` | Yes | PostgreSQL URL supplied by the database provider |
| `CACHE_URL` | Yes | Redis URL supplied by the cache provider |

The individual `POSTGRES_*` fields support local or self-hosted PostgreSQL.

### SMTP and mailboxes

| Variable | Secret | What to enter |
| --- | --- | --- |
| `EMAIL_HOST` | No | SMTP hostname |
| `EMAIL_PORT` | No | Usually `587` |
| `EMAIL_HOST_USER` | Treat as private | SMTP username/authenticated mailbox |
| `EMAIL_HOST_PASSWORD` | Yes | SMTP credential or app password |
| `EMAIL_USE_TLS` | No | Usually `True` with port 587 |
| `EMAIL_USE_SSL` | No | Usually `False` with port 587 |
| `DEFAULT_FROM_EMAIL` | No | Verified transactional sender |
| `SUPPORT_EMAIL` | No | Monitored support inbox |
| `MEETING_FROM_EMAIL` | No | Verified meeting/calendar sender |

The SMTP provider must authorize every From address. Configure SPF, DKIM, and
DMARC for the sending domain.

### Private upload storage

| Variable | Secret | What to enter |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | Yes | Restricted S3/S3-compatible access-key ID |
| `AWS_SECRET_ACCESS_KEY` | Yes | Matching secret key |
| `AWS_STORAGE_BUCKET_NAME` | Treat as private | Private bucket name |
| `AWS_S3_REGION_NAME` | No | Bucket region |
| `AWS_S3_ENDPOINT_URL` | No | Provider endpoint; blank for standard AWS |
| `AWS_QUERYSTRING_AUTH` | No | Keep `True` for private files |

Use an identity restricted to the RepRoot upload bucket.

## Google Calendar and Meet

Keep `GOOGLE_CALENDAR_ENABLED=False` until every credential is present.

| Variable | Secret | What to enter |
| --- | --- | --- |
| `GOOGLE_CALENDAR_CLIENT_ID` | Treat as private | Google OAuth web client ID |
| `GOOGLE_CALENDAR_CLIENT_SECRET` | Yes | Google OAuth client secret |
| `GOOGLE_CALENDAR_REFRESH_TOKEN` | Yes | Offline token for the calendar owner |
| `GOOGLE_CALENDAR_ID` | Treat as private | Business calendar email/calendar ID |
| `GOOGLE_CALENDAR_ENABLED` | No | Change to `True` after setup |

Private Calendar operations require OAuth; an API key is insufficient.

## Stripe billing

Use test-mode values until the payment flow and webhook are verified.

| Variable | Secret | What to enter |
| --- | --- | --- |
| `STRIPE_PUBLISHABLE_KEY` | No | Stripe publishable key |
| `STRIPE_SECRET_KEY` | Yes | Stripe backend secret/restricted key |
| `STRIPE_WEBHOOK_SECRET` | Yes | Webhook signing secret |
| `STRIPE_PRO_PRICE_ID` | No | Recurring Pro price ID |
| `STRIPE_PREMIUM_PRICE_ID` | No | Alternate/legacy Premium price ID |
| `STRIPE_PREMIUM_UNLIMITED_PRICE_ID` | No | Premium Unlimited recurring price ID |
| `REPROOT_BILLING_TEST_MODE` | No | `True` for simulation; otherwise `False` |
| `REPROOT_BILLING_PROVIDER` | No | Set to `razorpay` |
| `RAZORPAY_KEY_ID` | No | Razorpay test/live public key ID; backend checkout response may use it |
| `RAZORPAY_KEY_SECRET` | Yes | Matching Razorpay backend key secret |
| `RAZORPAY_WEBHOOK_SECRET` | Yes | Secret created for the RepRoot Razorpay webhook |
| `RAZORPAY_BASE_URL` | No | Razorpay API root, normally `https://api.razorpay.com` |
| `RAZORPAY_PERSONAL_LINK` | No | Optional Razorpay dashboard/support payment link |

Configure the Razorpay webhook destination as
`https://<your-backend-host>/api/accounts/billing/razorpay/webhook/` and enable
`payment_link.paid` and `payment.captured`. Use test credentials in Test and
live credentials only in Production.

## Synthetic 90-day demo data

The development seed creates one completed trainer profile, 50 synthetic client
profiles, groups, forms, templates, references, assignments, chat, and 90 days
of tracking entries for every client. It never prints passwords or tokens.

Before running it, manually set these development-only values in the backend
environment:

```dotenv
REPROOT_DEMO_TRAINER_PASSWORD=<choose-a-temporary-trainer-password>
REPROOT_DEMO_CLIENT_PASSWORD=<choose-a-temporary-shared-client-password>
```

Then run:

```powershell
.\.venv\Scripts\python.exe manage.py seed_demo_fitness_data --clients 50 --days 90
```

The trainer username is `maya_coach`, email is
`maya.coach@example.com`, and professional code is `coach-maya`. Client
usernames include `alex_rivera` through the named demo set, followed by
`demo_client_11` through `demo_client_50`. All generated client email addresses
are reserved example addresses and contain no real personal information.

Only the publishable key may be exposed if a future Stripe client flow needs
it. Stripe secret and webhook keys remain backend-only.

## Frontend and mobile

Angular and Flutter need only the public backend URL. Angular receives
`API_BASE_URL`/`RENDER_API_BASE_URL` while generating `app-config.js`. Flutter
receives:

```text
flutter build apk --dart-define=API_BASE_URL=https://api.your-domain.com
```

The backend URL is public routing information, not a credential.

## Before adding real secrets

1. Confirm `backend/.env` is ignored and untracked.
2. Confirm frontend/mobile scans contain no provider secrets.
3. Commit and deploy the code and template first.
4. Add real values only to `backend/.env` locally and the production secret
   dashboard remotely.
5. Restore strict no-read/no-edit environment rules in `AGENTS.md`.
6. Restart/redeploy and verify only configuration presence—not values.
