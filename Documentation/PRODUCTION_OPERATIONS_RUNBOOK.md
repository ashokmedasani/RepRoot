# RepRoot Production Operations Runbook

Last updated: 2026-07-30  
Initial supported launch regions: India and United States

This runbook covers operations outside the application repository. Never place
production credentials in Git, logs, tickets, screenshots, or documentation.
Real values belong only in the hosting provider's environment/secret settings.

## 1. Release gate

Before every production release:

1. Review the Git diff and confirm no environment, credential, database dump,
   uploaded media, or generated log is staged.
2. Run Django tests, `manage.py check --deploy`, `manage.py makemigrations
   --check --dry-run`, and the Angular production build.
3. Create an RDS manual snapshot before a migration or risky release.
4. Deploy backend, run migrations exactly once, and verify `/api/health/`.
5. Deploy frontend and test the root page, professional sign-up, Google login,
   client login, upload/download, and billing status.
6. Verify that API, website, and uploaded-file URLs use HTTPS.
7. Confirm error-alert email delivery without including request bodies or
   secret values.

## 2. Required recurring jobs

The application does not run maintenance commands automatically. Configure AWS
EventBridge Scheduler (or an equivalent private scheduler) to invoke these
commands in the backend environment:

- Daily: `python manage.py check_account_lifecycle`
- Daily: `python manage.py process_subscription_cancellations`
- Daily: `python manage.py run_retention`

Use a dedicated least-privilege execution role. Alert on non-zero exit status
and missed schedules. Command names must be rechecked with `manage.py help`
before creating production schedules.

## 3. Backups and recovery

### RDS PostgreSQL

- Enable automated backups with at least 14 days of retention for test launch;
  increase to 35 days before a broad public launch if the budget permits.
- Enable deletion protection, encrypted storage, and copy tags to snapshots.
- Take a manual snapshot before schema changes.
- Restrict PostgreSQL inbound access to the backend security group. Do not
  leave `0.0.0.0/0` inbound access enabled.
- Perform a quarterly restore drill into an isolated database. Run migrations,
  verify row counts and representative tenant access, then destroy the drill
  environment.

### S3 private uploads

- Keep Block Public Access enabled.
- Enable versioning, default encryption, and lifecycle rules for old versions.
- Grant the backend instance role only the required bucket/object actions.
- Use AWS Backup or cross-account backup if the acceptable recovery point
  cannot be met with versioning alone.
- Test restoration of representative profile images and client documents
  without changing production objects.

Record every restore drill with the snapshot/version used, start and finish
times, validation results, and person approving deletion of the drill copy.

## 4. Monitoring and alerts

Create CloudWatch alarms for:

- Elastic Beanstalk environment health below OK.
- HTTP 5xx rate and application error count.
- EC2 CPU, disk, and memory pressure.
- RDS CPU, free storage, connections, and failed connections.
- RDS automated backup failure.
- S3 4xx/5xx request anomalies.
- AWS estimated charges at 50%, 75%, 90%, and 100% of the monthly budget.

Configure `ERROR_ALERT_EMAIL` as a private operations mailbox. Application
alerts contain an error reference and sanitized summary; detailed investigation
must happen in the restricted admin console.

## 5. Incident response

1. Preserve timestamps, error references, deployment version, and affected
   tenant identifiers. Do not copy secrets or full request bodies.
2. Contain the incident: revoke exposed credentials, terminate sessions, limit
   network access, or roll back the release.
3. Determine which users and data were affected using tenant-scoped audit
   records.
4. Restore service from a known-good version or backup.
5. Assess notification duties with qualified counsel. India and United States
   rules and timelines vary by incident and state.
6. Record root cause, corrective action, and verification evidence.

## 6. Legal and regional launch gate

The application currently permits new professional profiles only for India and
the United States. Do not enable EEA, UK, or Australia until qualified counsel
has reviewed:

- controller/processor allocation and data-processing terms;
- health/sensitive-data consent requirements;
- international transfer safeguards and local representatives;
- child/minor access rules;
- state privacy notices and consumer request handling;
- breach notification procedures; and
- billing, cancellation, tax, and refund requirements.

The published Terms and Privacy Policy are product implementation text, not a
substitute for advice from counsel. Before public launch, fill the operator's
legally required identity/address disclosures outside source control where
applicable and obtain written legal approval of the final rendered documents.

## 7. Razorpay go-live gate

Keep billing test mode disabled in production until all items pass:

- Separate Razorpay test and live credentials.
- Webhook secret configured only in backend secret settings.
- Webhook URL uses HTTPS and signature verification succeeds.
- Successful, failed, duplicated, delayed, and amount-mismatch events tested.
- Payment amount/currency matches the server catalog.
- Cancellation, expiration, refund, and dispute behavior documented.
- Reconciliation compares the Razorpay dashboard with finance-ledger entries.

The present checkout uses prepaid Razorpay Payment Links. It must not be
described as automatically renewing unless a real Razorpay Subscriptions flow
is implemented and tested.

