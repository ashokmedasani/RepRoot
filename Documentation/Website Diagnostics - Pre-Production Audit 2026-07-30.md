# RepRoot Website Diagnostics — Pre-Production Audit

**Audit date:** 2026-07-30  
**Branch and baseline:** `Test` at `a031c58` (`Correct Render API origin configuration`)  
**Scope:** Django backend and Angular website only  
**Excluded:** Flutter/mobile, real environment files, live secret values, payment-provider transactions  
**Change policy:** No application source code was changed. No migrations, commits, or pushes were performed.

## Executive decision

**Result: NOT CLEARED for a production commit or production launch yet.**

The current website build and backend regression suite pass, and the inspected API authorization patterns are generally well scoped. However, the working tree is very large and contains confirmed production blockers in newly introduced storage, billing, and Google authentication workflows. The current changes should remain uncommitted as one production release until the blockers below are corrected and retested.

## Repository and baseline comparison

- Current baseline: commit `a031c58` on `Test`, matching `origin/Test`.
- Working tree at audit time: **113 tracked modified files**, **24 untracked paths**, **0 staged files**.
- Website/backend/documentation diff: **98 files**, approximately **6,802 insertions and 3,289 deletions**.
- The change set adds or substantially changes Google authentication, scheduling, resource/category terminology and migrations, plan locking, subscription cancellation, Razorpay billing, forms/groups, dashboards, profiles, templates, payments, and error reporting.
- Because the working tree is dirty, the previous version was compared through Git diffs and `HEAD` content. The repository was not checked out, reset, or otherwise altered.
- This is too broad for a low-risk single production commit. Separate, reviewable commits are recommended after fixes: migrations/models, authentication, billing/cancellation, resource storage, scheduling, and frontend UX/API integration.

## Confirmed production blockers

### P0 — Resource relocation can corrupt the stored file reference

**Location:** `backend/accounts/resource_cold_storage.py`, `_relocate`

The code calls `storage.save(new_name, content)` but ignores the name returned by the storage backend. Django storage backends can return a different name when the requested destination already exists. The code then deletes the old object and stores the originally requested name in the database.

Potential result:

- the model can point to an older or unrelated object;
- the newly saved object can become orphaned;
- the original source is already deleted;
- downgrade/upgrade lock synchronization can therefore cause a broken resource or data loss.

The implementation also loads each entire file into application memory. Large files or multiple lock transitions can cause memory pressure on a small production instance.

**Required before production:** use the actual name returned by `storage.save`, verify the destination before deleting the source, make the operation recoverable/idempotent, stream or copy server-side where supported, and add collision/failure tests.

### P0 — Billing state is coupled incorrectly to test mode

**Location:** `backend/accounts/views.py`, billing overview and checkout views

The billing overview reports `billing_configured` and every `available_upgrades` value from `REPROOT_BILLING_TEST_MODE`, not from the actual Razorpay/payment configuration. When test mode is disabled for production, the UI can report that billing is unavailable even when the payment provider is configured.

The checkout view also contains unreachable legacy Stripe code after the Razorpay response. This makes the intended production workflow ambiguous and leaves two provider architectures in one path.

**Critical configuration rule:** if `REPROOT_BILLING_TEST_MODE` is accidentally enabled in production, an authenticated professional can change paid plan tiers without payment.

**Required before production:** calculate provider readiness independently from test mode, remove unreachable provider code, test the live-disabled and live-enabled states, and enforce a startup/deployment guard that prevents test billing mode in production.

### P1 — Google sign-in uses Google's token-info debugging endpoint

**Location:** `backend/accounts/google_oauth.py`

Google ID tokens are verified by sending the raw token in a query parameter to Google's `tokeninfo` endpoint. The source itself notes that this endpoint is intended for debugging and can be rate limited.

Risks:

- authentication availability depends on a synchronous external debugging endpoint;
- the ID token is placed in a URL and may be recorded by upstream/proxy logs;
- rate limiting can break sign-in under real traffic.

Audience, issuer, email verification, email, and subject checks are present, which is good.

**Required before production:** verify tokens locally using Google's supported authentication library and cached signing keys; add invalid audience, issuer, expiry, and network-independence tests.

### P1 — Production API URL can silently fall back to HTTP port 8000

**Locations:** frontend runtime configuration and API services

If runtime configuration is absent or blank, multiple services fall back to:

`http://<current-host>:8000/api/accounts`

On the HTTPS production site this creates mixed-content failures and recreates the earlier “start Django on port 8000” behavior. A missing production setting should not silently construct an insecure development URL.

**Required before production:** fail closed with a clear configuration error in production, preserve the port-8000 fallback only for explicit local development, and run a production artifact test against `https://api.rep-root.com`.

## High-priority production risks

### P1 — Browser tokens are exposed to JavaScript

- Professional tokens are stored in `localStorage`.
- Admin/client tokens are stored in `sessionStorage`.

Any successful cross-site scripting issue can read and exfiltrate these tokens. `localStorage` also persists the professional session beyond a browser session.

**Recommendation:** move authentication to Secure, HttpOnly, SameSite cookies with CSRF protection, or document and accept the risk with a strong Content Security Policy and a short token lifetime before public production use.

### P1 — High-risk rename migration needs a restored-data rehearsal

Migrations `0028` through `0032` rename reference/category concepts, alter notification preferences, add plan-lock ordering, add client suspension state, and add cancellation targeting.

The local migration graph is consistent and all migrations through `0032` are applied locally. That does not prove the migration is safe on real existing data. Migration `0029` can discard the old preference row when both old and new category rows already exist.

**Required before production:** restore a production-like database snapshot into an isolated database, run the complete migration chain, compare row counts and relationships before/after, verify rollback/restoration procedures, and take an RDS snapshot immediately before deployment.

### P1 — Cancellation can remain pending indefinitely after its effective date

At the effective date, a cancellation is refused when storage exceeds the target plan, but the cancellation fields remain scheduled. There is no verified notification/escalation path in the audited tests for this state.

**Recommendation:** define and test the customer-visible state, notification, retry behavior, support escalation, and provider-side cancellation behavior when local downgrade is blocked.

### P2 — Payment/webhook error handling needs hardening

- Raw provider exception text is returned in some billing API responses.
- Razorpay webhook JSON parsing is not guarded after signature verification; malformed signed content can raise a server error.
- Payment behavior was not transaction-tested because real credentials and live external mutations were outside this audit.

Return stable customer-safe errors, log provider details only in protected server logs, and add malformed payload and idempotency tests.

### P2 — “Cold” prefix does not itself reduce storage cost

Moving an S3 object to a different key prefix does not change its S3 storage class. Cost reduction depends on a separately configured and verified S3 lifecycle policy. Treat this as an operational dependency, not an application guarantee.

## Positive findings

- Django backend regression suite: **71 tests passed** for `accounts` and `admin_portal`.
- Django model/migration drift check: **no changes detected**.
- Python package consistency: `pip check` reported **no broken requirements**.
- Python compilation check completed successfully.
- Angular production build completed successfully.
- Local backend health endpoint returned HTTP 200 with `{"status":"ok"}`.
- Username and email availability endpoints returned expected HTTP 200 responses for non-existent audit values.
- Google authentication rejected an empty credential with HTTP 400.
- Scheduling tests cover overlapping availability blocks and passed.
- Error reporting accepts pre-login reports intentionally and is protected by a scoped throttle.
- Inspected resource endpoints scope professional-owned records to the authenticated professional; no confirmed IDOR was found in the inspected paths.
- No obvious AWS access-key or private-key signature was found in the scoped source scan. Real environment/secret files were deliberately excluded and never accessed, so this is not a certification that deployment settings contain no exposed secret.
- Google OAuth client ID is present in public frontend configuration. A client ID is public metadata, not a secret; client secrets must never be placed there.

## Test limitations and warnings

- The frontend was not listening on the stated port 4300 at audit time. A temporary local start attempt never bound the port, so browser workflow testing could not be completed.
- The Angular project has no configured `test` target. `npm test` cannot run; therefore no frontend unit regression suite exists in the current project configuration.
- The production build warned that `professional-account-settings.component.scss` exceeds its 20 kB warning budget by 29 bytes. This does not fail the build.
- `manage.py check --deploy` reported six warnings in the currently running local configuration: HSTS, SSL redirect, secret key strength, secure session cookie, secure CSRF cookie, and DEBUG. Because real deployment settings are user-managed and were not read, verify these values manually in AWS before production. The local warnings do not by themselves prove the deployed environment is unsafe.
- The dependency vulnerability audit could not be completed in the restricted environment. Running `npm audit` transmits dependency metadata to an external registry and requires the user's explicit approval.
- Google, SMTP, Razorpay, AWS S3, CloudFront, Render, and production DNS integrations were not mutated or transaction-tested.
- Existing live data was not changed. No migrations, seed commands, payment calls, email sends, or destructive tests were executed.

## Deployment configuration checklist (manual verification; do not expose values)

In AWS Elastic Beanstalk/secret management, verify presence and production-safe values without pasting values into Git or this report:

- production debug disabled;
- strong unique Django secret key;
- HTTPS redirect enabled;
- Secure session and CSRF cookies enabled;
- trusted HTTPS origins and allowed hosts contain only intended domains;
- HSTS is enabled only after HTTPS is confirmed across all intended subdomains;
- payment test mode disabled;
- payment enablement matches the planned launch state;
- API base URL used by the Render build is the HTTPS API domain;
- S3 bucket, region, access policy, CORS, and lifecycle policy are correct;
- SMTP sender/domain/IP restrictions are correct;
- Google OAuth authorized origins match the website domains.

After changes to deployment variables, redeploy/restart the relevant service. Do not put secrets into frontend runtime configuration.

## Required retest gate before commit

1. Correct every P0 and P1 item.
2. Add backend tests for file-name collisions, storage failure recovery, billing production/test-mode separation, webhook malformed payloads, and cancellation blocked by storage.
3. Add a frontend test target and cover API configuration failure, authentication, forms/groups multi-form selection, billing visibility, and plan cancellation.
4. Start the website on port 4300 and execute an end-to-end smoke test with backend port 8000:
   signup/OTP, login, profile setup with image, forms/groups, multiple form links, clients, templates, resources, schedule, plan change/cancel, logout, and authorization boundaries.
5. Build the exact Render production artifact and verify it calls only `https://api.rep-root.com`.
6. Rehearse migrations against a restored production-like database and compare data.
7. Run approved dependency vulnerability scans.
8. Re-run Django deploy checks using the actual production deployment configuration without printing secrets.
9. Review and split the large change set into coherent commits.
10. Confirm `git status`, inspect all untracked files, and verify no environment file, secret, log, database, build output, or credential is staged.

## Commit recommendation

**Do not commit or push the full current change set as production-ready yet.**  
Once the blockers are fixed and the retest gate is green, create scoped commits and perform a final baseline-to-release comparison. A commit should be the result of the audit, not a way to preserve an unverified production release.
