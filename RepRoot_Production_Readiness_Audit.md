# RepRoot Studio — Production Readiness Audit

**Scope:** Read-only review of the Django backend (`backend/`) and Angular frontend (`frontend/`). No code was changed to produce this report. Findings are based on direct inspection of `settings.py`, `.env`, URL/view/middleware/auth code, `requirements.txt`, `package.json`, git history, and targeted searches across both codebases for secrets, hardcoded personal data, and debug artifacts.

**Bottom line:** The backend was clearly built with production in mind — it has real boot-time guardrails that refuse to start in an insecure configuration. The gap between where you are today and "actually live" is mostly about *supplying real values* (a real database, a real email provider, real Stripe keys, a real domain) rather than *writing more code*. The items below are organized so you can work top to bottom.

---

## 1. What's already solid (no action needed)

- **`settings.py` self-protects.** If `DJANGO_DEBUG=False`, the app refuses to boot unless: `DJANGO_SECRET_KEY` has been changed from the dev default, a real email backend is configured, and S3-compatible storage (`AWS_STORAGE_BUCKET_NAME`) is set. This is exactly the kind of guardrail that prevents an accidental insecure launch — most projects don't have this.
- **Security headers/cookies are wired correctly**: `SECURE_SSL_REDIRECT`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, HSTS, `X_FRAME_OPTIONS`, `SECURE_CONTENT_TYPE_NOSNIFF`, `SECURE_REFERRER_POLICY` all default to safe values automatically once `DEBUG=False`. Nothing to change here, just confirm your host forwards `X-Forwarded-Proto` correctly (Render does this by default).
- **`.env` is not, and has never been, committed to git.** Confirmed via `.gitignore` and a repo history check for the file — no secret leakage there.
- **No hardcoded secrets or real personal data found in tracked source.** Searched both codebases for API-key-shaped strings (`sk_live_`, `AKIA...`, `AIza...`, etc.), Gmail/Yahoo/Outlook-style emails, and phone numbers — none found in application code. All demo/seed data uses fake `@example.com` / `@reproot.local` addresses.
- **Stripe webhook is properly verified.** `stripe.Webhook.construct_event(...)` checks the signature and the endpoint returns `503` (not a silent pass-through) if `STRIPE_WEBHOOK_SECRET` isn't configured — it never trusts an unsigned payload.
- **Rate limiting is applied broadly and consistently** via DRF's `ScopedRateThrottle` across login, OTP, public registration/lead forms, support, error-reporting, and payment endpoints — not just bolted onto one or two views.
- **File uploads are validated** (content-type/size checks) across professional and client upload paths, per the earlier security pass.
- **Media storage cleanly swaps** from local disk (dev) to S3-compatible object storage (prod) behind one env var, and the app won't boot without it in production — so there's no way to accidentally ship with uploads going to ephemeral local disk.
- **Frontend API URL is injected at deploy time**, not baked into the JS bundle (`public/app-config.js`, written by `scripts/write-app-config.mjs` from `API_BASE_URL`/`RENDER_API_BASE_URL`). This is the correct pattern for one build artifact deployed across environments.
- **No `console.log`/`debugger` left in frontend application code**, and no `print()`/`pdb.set_trace()`/TODO/FIXME litter found in the backend `accounts` app.
- **Dependencies are pinned to safe ranges**, not left on `latest`, in both `requirements.txt` and `package.json`.
- **Deploy script is clean**: `render_start.sh` only runs `migrate`, `collectstatic`, then starts `gunicorn` — none of the demo/seed management commands are wired into the deploy path.

---

## 2. Must configure before going live (blocking)

These are all *already gated* by the code (it will refuse to boot without them) — but a placeholder that merely satisfies the boot check isn't the same as a working one. Each needs a real value, not just a non-empty one.

1. **`DJANGO_SECRET_KEY`** — currently `local-development-only-secret-key` in your dev `.env`. Generate a real random secret (50+ chars) and set it as an environment variable on your host. Never put it back in a `.env` file that could get committed.
2. **`DJANGO_DEBUG`** — must be `False` in production. Confirm this is explicitly set on the host, don't rely on the code default.
3. **Email delivery** — `.env` currently has `EMAIL_HOST_USER=your-email@gmail.com` / `EMAIL_HOST_PASSWORD=your-app-password`, i.e., unfilled placeholders. The boot check only blocks the *console* backend, not a broken SMTP one — you must actually set up and test a real transactional sender (a proper Gmail app password, or better, SendGrid/Postmark/Mailgun/SES for deliverability and volume) before relying on password resets, credential emails, and meeting invites reaching real inboxes.
4. **Object storage (S3)** — `AWS_STORAGE_BUCKET_NAME`, access keys, and region are blank in dev. Provision a real bucket, create a scoped IAM user (upload/read/delete on that bucket only — not a root key), and set the CORS policy on the bucket if the frontend ever uploads directly.
5. **Stripe** — `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`, and the per-tier price IDs (`STRIPE_PRO_PRICE_ID`, `STRIPE_PREMIUM_UNLIMITED_PRICE_ID`) are all blank in dev. You need to: create real Products/Prices in Stripe for Pro and Premium Unlimited, switch to live keys, and register a live webhook endpoint pointing at `/api/accounts/.../stripe-webhook` (whatever your route is) with its own signing secret. Also make a **deliberate decision** about `REPROOT_BILLING_TEST_MODE` — its default flips to `False` once `DEBUG=False`, meaning upgrade checkout will try to use real Stripe prices. If you're not ready to charge real cards on launch day, decide explicitly whether to keep test mode on (free auto-upgrades) or finish the Stripe setup first — don't let this happen by omission.
6. **Database** — the dev fallback defaults to `POSTGRES_USER=postgres` / `POSTGRES_PASSWORD=postgres`, which is fine locally but must not carry into production. Set a real `DATABASE_URL` pointing at a managed Postgres instance with a strong, unique password.
7. **`DJANGO_ALLOWED_HOSTS`, `CORS_ALLOWED_ORIGINS`, `CSRF_TRUSTED_ORIGINS`** — currently scoped to `localhost`/`127.0.0.1`. These must include your real production domain(s) (both the bare domain and `www.` if you use both) or every browser request will fail once deployed.
8. **`REPROOT_FRONTEND_URL`, `REPROOT_BILLING_SUCCESS_URL`, `REPROOT_BILLING_CANCEL_URL`** — all default to `http://localhost:4300`. If left unset in production, password-reset links, notification emails, and post-checkout redirects will send real users back to `localhost`. Set these to your real frontend URL.
9. **Frontend `API_BASE_URL`** — set this build-time env var to your deployed backend's real URL when running `npm run build:render` (or however your CI builds it). An empty value only works if frontend and backend are served from the exact same origin.

---

## 3. Personal / test data inventory — what to clear before launch

This is the part you specifically asked about: everywhere test or personal-looking information currently lives.

- **`.env` placeholders** (listed above: Gmail placeholder, dev secret key, `postgres`/`postgres` DB credentials) — replace with real production secrets set as environment variables on your host, never re-added to a file that could be committed.
- **Test accounts in the database you've been testing against during this review**: a professional account (`ashokt26`) and client accounts including `rahulverma` and "Priya Sharma" (`priya.sharma.test@example.com`, phone `9876543210`, and likely others created along the way while we worked through fixes together). I don't have network access to your live Postgres instance from this session, so I can't hand you an exact row-by-row list — before launch, open the admin portal (or query the database directly) and review every `ProfessionalProfile` and `ClientAccess` record, removing anything that isn't a real customer.
  - **Cleanest option:** don't carry this dev database into production at all. Point production at a brand-new, empty managed Postgres database and let real signups populate it from zero. That sidesteps needing to hunt down every test row individually.
- **Demo/seed management commands** (`seed_demo_fitness_data`, `seed_graced_account`, `seed_locked_account`, `seed_low_usage_account`, `seed_over_quota_account`, `seed_warning_threshold_account`, `seed_scale_fitness_data`, `seed_manual_payment_history`) — these only use fake `@example.com`/`@reproot.local` data and are never invoked automatically by the deploy script, so they're safe as-is. Just treat them as dev-only tools and don't run them against the production database.
- **Admin staff accounts** — create your real production admin account fresh via `create_admin_staff` once deployed (it requires an explicit password and validates it — no hardcoded default). Don't reuse whatever staff credentials exist in your dev environment.

---

## 4. Should-fix soon (not launch-blocking, but real gaps)

1. **Auth tokens never expire.** Both professional login tokens (DRF `TokenAuthentication`) and client portal tokens (`ClientAuthToken`) are valid indefinitely until something explicitly deletes/rotates them (logout, password reset). There's no automatic session timeout or "log out everywhere" mechanism. For an app holding client health/fitness data, worth deciding whether this is an accepted risk or whether to add expiry.
2. **Django admin is at the default `/admin/` path.** Still requires real staff credentials, so not a vulnerability by itself, but it's the first thing automated scanners try. Consider moving it to a non-default path or adding IP allowlisting for extra depth.
3. **No external error monitoring/alerting.** You have a solid internal `ErrorLog` model and admin error console (`ErrorCaptureMiddleware`), but nothing pages you at 2am if something breaks. Worth wiring up Sentry or similar before real users depend on uptime.
4. **Throttle rates are reasonable defaults but untested under real load** (`20/min` auth, `5/min` OTP, etc.). Worth a quick sanity check that these won't lock out legitimate users on a shared office IP, and that they're tight enough to actually deter brute-force attempts.

---

## 5. Suggested order of operations

1. Stand up a fresh production Postgres database (don't migrate the dev one).
2. Set every environment variable in Section 2 on your hosting platform (not in a file).
3. Deploy backend, run `create_admin_staff` for your real admin account.
4. Confirm email deliverability with a real test send.
5. Finish Stripe product/price setup and decide on `REPROOT_BILLING_TEST_MODE` deliberately.
6. Point the frontend build at the real backend URL, deploy, and do one full manual pass through signup → login → core flows on the live domain.
7. Revisit Section 4 once you're stable and have real users.

---

*This report reflects a static code/config review only — it does not replace a live penetration test or a legal/compliance review (data protection, payment handling, etc.) if you plan to operate at scale.*
