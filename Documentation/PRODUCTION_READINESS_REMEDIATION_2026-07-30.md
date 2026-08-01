# RepRoot Website Production-Readiness Remediation

Date: 2026-07-30  
Scope: Django backend and Angular website only  
Target launch: India and United States  
Status: Application changes complete for this pass; deployment gates remain

## Executive decision

The website code is suitable for a controlled test launch after the deployment
checklist below is completed. It is **not yet approved for unrestricted
production launch** because real Razorpay testing, production environment
verification, backup/restore verification, and qualified legal review cannot
be completed from source code alone.

EEA, United Kingdom, and Australia professional onboarding is intentionally
restricted until the additional privacy, transfer, representation, health-data,
consumer, and minor-user requirements have been reviewed.

## Completed in this remediation

### Authentication and browser security

- Professional and client API tokens now have a configurable server-side
  lifetime and rotate during a new sign-in after expiry.
- Professional browser tokens moved from persistent local storage to tab-scoped
  session storage.
- Production API services no longer silently fall back to an insecure
  `http://host:8000` URL. That fallback is limited to recognized local hosts.
- Render static-site headers add content-type protection, frame blocking,
  referrer control, permissions restrictions, HTTPS upgrades, and a frontend
  Content Security Policy compatible with Google Identity Services.

### Consent and regional scope

- Password and Google sign-up now require explicit Terms and Privacy acceptance.
- The backend records acceptance timestamps and the accepted legal-document
  version.
- Google login can still access an existing account, but Google cannot create a
  new account without acceptance from the sign-up page.
- Professional profile setup accepts India and United States only by default.
- Terms and Privacy pages were rewritten for the actual product, providers,
  sensitive wellness data, retention, billing behavior, and regional scope.

### Billing integrity

- Checkout uses the configured payment throttle.
- Razorpay webhook parsing rejects malformed bodies without raising a server
  error.
- Signed callbacks validate user, plan, billing cycle, amount, currency, paid
  status, and the payment-link identifier.
- Callback idempotency is protected by a unique provider/event database record.
- Plan activation and finance-ledger creation happen in one atomic transaction.
- Plan expiry uses calendar months instead of fixed 30-day approximations.
- Current Razorpay Payment Links are accurately treated as prepaid membership
  terms. They are not represented as automatic recurring subscriptions.

### Error handling and operations

- Error reports redact common password, token, authorization, OTP, and API-key
  patterns from messages, stack traces, paths, and nested context.
- New errors can send a sanitized reference email to a private operations
  mailbox.
- Old application error logs are removed by the lifecycle command using a
  configurable retention period.
- A production runbook now covers releases, scheduled lifecycle jobs, AWS
  alarms, RDS/S3 backups, restore drills, incidents, and the Razorpay go-live
  gate.

## Verification evidence

- Django system check: passed with zero issues.
- Migration drift check: passed; migration `0033` matches the models.
- Accounts, Google Calendar, and notifications: 56 tests passed.
- Admin portal: 16 tests passed.
- Total executed backend tests: 72 passed.
- Python dependency consistency (`pip check`): passed.
- Angular Render production build: passed.
- Frontend build warning: account-settings stylesheet is 532 bytes over its
  advisory 20 KB component budget; this does not fail the build.
- Focused secret-pattern scan excluding real environment files, dependencies,
  build output, and logs: no private-key, AWS access-key, Stripe secret-key, or
  Razorpay secret-key pattern found.

## Deployment gates still required

1. Run migration `0033` during the backend deployment.
2. Manually set the required environment names from `.env.example` in the
   private hosting settings. Do not put real values in Git.
3. Run `manage.py check --deploy` inside the production environment. It must
   report no warnings for debug, secret key, HTTPS redirect, HSTS, session
   cookies, or CSRF cookies.
4. Restrict RDS inbound PostgreSQL access to the backend security group and
   remove public `0.0.0.0/0` database access.
5. Verify RDS automated backup retention and deletion protection; perform and
   record a restore drill.
6. Verify S3 Block Public Access, encryption, versioning, and lifecycle/backup.
7. Configure the three daily maintenance commands in the operations runbook
   and alert on failures.
8. Obtain qualified legal review of the final rendered Terms and Privacy Policy,
   operator identity/address disclosures, minor-user rules, health-data
   language, state-law obligations, and refund/cancellation language.
9. Complete Razorpay test-mode payment tests: success, failure, duplicate
   webhook, delayed webhook, wrong amount, refund, dispute, cancellation, and
   reconciliation.
10. If automatic renewal is required, implement and test Razorpay Subscriptions.
    Payment Links alone do not provide recurring membership billing.
11. Test two separate professionals and at least two clients per professional in
    the deployed environment, including attempts to use another tenant's IDs.
12. Verify error-alert email, health alarms, and a controlled 500 response.

## Manual environment additions

Add these names in the backend deployment environment, using private values
where applicable:

- `REPROOT_AUTH_TOKEN_TTL_HOURS=12` — non-secret; token lifetime.
- `REPROOT_PROFESSIONAL_LEGAL_VERSION=2026-07-30` — non-secret; professional consent evidence.
- `REPROOT_CLIENT_LEGAL_VERSION=2026-07-30` — non-secret; client consent evidence.
- `REPROOT_LEGAL_EFFECTIVE_DATE=2026-07-30` — non-secret; shared effective date displayed across all current legal documents.
- `REPROOT_SUPPORTED_COUNTRIES=IN,INDIA,US,USA,UNITED STATES,UNITED STATES OF AMERICA`
  — non-secret; launch scope.
- `REPROOT_ERROR_LOG_RETENTION_DAYS=90` — non-secret; diagnostic retention.
- `ERROR_ALERT_EMAIL=<private-operations-alert-mailbox>` — private operational
  address, supplied by the mailbox administrator.

Restart or redeploy the backend after changing these values.
