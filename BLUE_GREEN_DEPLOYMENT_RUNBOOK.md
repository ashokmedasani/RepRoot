# RepRoot Blue/Green Deployment Runbook

This is the repeatable release process for RepRoot. It preserves the currently
working website and API while a replacement version is tested privately.

Do not record passwords, API keys, SMTP credentials, database passwords,
tokens, private keys, or real environment-variable values in this document.
Environment values remain user-managed and must be entered manually in the
hosting provider's protected settings.

## Release principles

- **Blue** is the environment currently serving users.
- **Green** is the replacement environment being prepared and tested.
- Public traffic remains on Blue until Green passes validation.
- A release uses one Git commit as its identity.
- The frontend build and backend ZIP must come from that exact commit.
- Never delete Blue until Green has remained healthy and rollback is no longer
  reasonably required.
- Never assume that reverting application code reverses a database migration.

## Current infrastructure

| Component | Current role | Known identifier |
| --- | --- | --- |
| Backend | Blue / currently running | `reproot-testing-api` |
| Backend application | Elastic Beanstalk application | `reproot-backend` |
| Backend region | AWS | `us-east-1` |
| Backend platform | Elastic Beanstalk Python | Python 3.13 on Amazon Linux 2023 |
| Backend version observed before this release | Rollback candidate; confirm again before release | `reproot-backend-7ae9204` |
| Public API | Current production-facing API | `https://api.rep-root.com` |
| Frontend | Current public Render service | Record in the release log |
| Database | Existing AWS RDS PostgreSQL | Identifier only: `reproot-testing-db` |

The current backend is a single-instance environment. A load balancer is not
required to perform blue/green deployment: Elastic Beanstalk can swap the
environment CNAMEs between two environments.

## Phase 1: Record and preserve Blue

Before uploading or changing anything:

1. Open Elastic Beanstalk > Applications > `reproot-backend` > Environments >
   `reproot-testing-api`.
2. Record its environment health, deployed application version, platform,
   environment URL, instance type, and configuration save name if one exists.
3. Open Render's current production Static Site.
4. Record its service name, latest successful deploy ID, Git branch, and commit.
5. Record the Git commit intended for the new release.
6. Create or confirm a current RDS snapshot before any release that may touch
   the database.
7. Do not edit production DNS, terminate Blue, or manually overwrite the live
   backend during preparation.

### Phase 1 checkpoint

- [ ] Blue Elastic Beanstalk version recorded
- [ ] Blue Elastic Beanstalk health is acceptable
- [ ] Current Render successful deploy recorded
- [ ] Release Git commit recorded
- [ ] Migration status reviewed
- [ ] RDS snapshot created or explicitly deferred with reason

## Phase 2: Create the Green backend

Recommended environment name: `reproot-testing-api-green`.

1. In CloudFormation, locate the stack associated with the Blue environment.
2. Confirm its operation status allows drift detection, such as
   `UPDATE_COMPLETE`.
3. Choose **Stack actions > Detect drift** and wait for completion.
4. Continue only when the stack drift status is `IN_SYNC`. If it is `DRIFTED`,
   review every drifted resource before cloning because out-of-sync changes may
   not be carried into Green. Treat security-group drift as critical.
5. In Elastic Beanstalk, select the existing Blue environment.
6. Choose **Actions > Clone environment** when available. Cloning is preferred
   because it copies platform and infrastructure configuration.
7. Set the new environment name to `reproot-testing-api-green`.
8. Keep it in `us-east-1` and in the same VPC as the current RDS database.
9. Confirm the platform matches Blue.
10. Confirm the EC2 instance profile and service role are correct.
11. Confirm the EC2 role has the required S3 policy attached.
12. Create Green without swapping URLs or changing public DNS.
13. Manually verify protected environment configuration in Green without
   displaying or recording secret values. Never paste protected values into
   source code or this runbook.
14. Deploy the backend ZIP built from the recorded release source.
15. Record the generated Green URL and deployed application-version label.

The current Gunicorn configuration uses two workers, two threads, safe request
recycling, and a 120-second timeout. This should reduce memory pressure on the
current small instance. Monitor Green before deciding whether to increase RAM.

### Phase 2 checkpoint

- [ ] Blue CloudFormation stack operation status checked
- [ ] Blue CloudFormation drift detection completed with `IN_SYNC`
- [ ] Green environment exists separately from Blue
- [ ] Green uses the intended platform, VPC, roles, and instance type
- [ ] Required protected configuration was entered manually
- [ ] New backend application version deployed successfully
- [ ] Green health reached Ready/Ok or any warning was explained
- [ ] Green `/api/health/` returns HTTP 200

## Phase 3: Choose database and storage isolation

### Safer staging arrangement

- Restore the latest RDS snapshot into a staging RDS instance.
- Point Green at the staging database.
- Use a staging S3 bucket or isolated prefix.
- Use test email recipients or a safe mail mode.

This prevents staging activity from changing live users' records.

### Shared-database compatibility test

Green may temporarily use the existing RDS database only when the release has
no incompatible migration. Any Green signup, edit, upload, email, meeting,
notification, or deletion can then affect live data. Keep testing read-only or
use specifically approved test records.

Before any schema change:

1. Create an RDS snapshot.
2. Review generated migrations.
3. Prefer backward-compatible expand-and-contract migrations.
4. Test the migration against a restored staging database.
5. Document the data rollback procedure separately from the code rollback.

## Phase 4: Create the staging frontend

Recommended Render service name: `reproot-web-staging`.

1. Create a separate Render Static Site from the same repository.
2. Select the exact release commit or its release branch.
3. Reuse the production build settings.
4. Manually set the staging site's public API base URL to the Green API URL.
5. Do not attach `rep-root.com`, `www.rep-root.com`, or
   `rep-root.com` to the staging service.
6. Deploy and record the Render deploy ID and temporary staging URL.
7. Treat the staging URL as public unless access control is explicitly added.
   An unadvertised URL is not private.

## Phase 5: Full private validation

Test through the staging Render URL only:

- [ ] RepRoot parent homepage
- [ ] RepRoot public homepage and `/portal` gateway
- [ ] `/portal` and professional/client navigation
- [ ] Professional signup, OTP, login, logout, and password reset
- [ ] Client login and professional search
- [ ] Current legal-document acceptance and version-change behavior
- [ ] Existing professional and client accounts
- [ ] Cross-user and cross-professional data isolation
- [ ] Forms, lead submissions, groups, and client onboarding
- [ ] Templates, recurring entries, references, and categories
- [ ] Meetings, schedules, reminders, and their notifications
- [ ] Chat and notification unread/read/clear behavior
- [ ] Client and professional profile-edit approval flows
- [ ] File upload, retrieval, permissions, and S3 access
- [ ] Payment functionality remains in the intended testing/locked state
- [ ] Mobile, tablet, laptop, and large-screen layouts
- [ ] Green `/api/health/` returns HTTP 200
- [ ] Browser console has no unexplained errors
- [ ] Backend logs have no unexplained 4xx/5xx or database errors
- [ ] API responses expose no secrets and no other user's data

Record failures with the page, account role, timestamp, expected behavior,
actual behavior, HTTP status, and relevant non-secret log message.

## Phase 6: Public switch

For a coordinated backend and frontend release:

1. Confirm the tested release commit has not changed.
2. Confirm the database snapshot and rollback versions.
3. Switch the backend first by swapping the Blue and Green Elastic Beanstalk
   environment URLs.
4. Verify `https://api.rep-root.com/api/health/`.
5. Verify one safe authenticated read and one approved write.
6. Deploy the exact tested commit to the production Render service.
7. Run the production smoke test below.

Do not rebuild from uncommitted local files between staging and production.

### Production smoke test

- [ ] RepRoot public pages load over HTTPS
- [ ] Portal and login pages load
- [ ] API health returns HTTP 200
- [ ] One professional can sign in and load the dashboard
- [ ] One client can sign in and load assigned data
- [ ] CORS and CSRF requests succeed
- [ ] One approved S3 read/upload test succeeds
- [ ] No sudden 4xx/5xx increase appears

## Phase 7: Monitor and retire Blue

Monitor for at least 30–60 minutes:

- Elastic Beanstalk environment and instance health
- Memory and CPU utilization
- HTTP 4xx/5xx rates
- Database connection failures
- Login, OTP, CORS, and CSRF failures
- S3 failures
- Render/browser errors

Keep the old environment for at least 24 hours when budget permits. Terminate
the unused environment only after Green remains healthy and the rollback window
has been formally closed.

## Rollback

### Backend rollback

1. Swap Elastic Beanstalk environment URLs back to Blue.
2. Verify public API health.
3. Do not delete Green; preserve it for diagnosis.
4. If a migration changed data, follow the documented database recovery plan.

### Frontend rollback

1. In Render, choose the previous recorded successful deploy.
2. Use Render's rollback/redeploy control.
3. Verify public routes and API compatibility.

## Release matrix

| Change | Recommended process |
| --- | --- |
| Text, styling, public pages | Staging Render > validate > production Render |
| Backend logic | Green Elastic Beanstalk > API tests > URL swap |
| Frontend and backend | Green backend > staging frontend > full test > backend switch > frontend switch |
| Terms/privacy version | Test content and acceptance behavior together, then coordinate both releases |
| Database schema | Snapshot > compatible migration > restored staging test > Green validation > controlled switch |

## Release log template

Copy this section for every release.

### Release: YYYY-MM-DD — short name

| Item | Recorded value |
| --- | --- |
| Release commit | Pending; current base is `486c5a51a397e40138368cd38c1ca74f51b56d71` |
| Blue EB environment | `reproot-testing-api` |
| Blue EB version | Pending confirmation |
| Blue health before release | Pending |
| Green EB environment | `reproot-testing-api-green` |
| Green EB version | Pending |
| Production Render service/deploy | `reproot-web` / commit `a031c58` / live July 28, 2026 10:25 AM |
| Production Render service ID | `srv-d9kajgvqj5pc73f0ua90` |
| Production Render branch | `Test` |
| Staging Render service/deploy | Pending |
| RDS snapshot identifier | Pending or documented deferral |
| Database strategy | Pending: isolated staging / shared compatibility test |
| S3 strategy | Pending: isolated / shared with restrictions |
| Public switch time | Pending |
| Rollback window closes | Pending |
| Final result | Pending |

#### Questions and decisions

- Add each deployment question and the final decision here.

#### Problems and resolutions

- Add the timestamp, symptom, root cause, action, and result here.

#### Final approval

- [ ] Backend validated
- [ ] Frontend validated
- [ ] Data safety validated
- [ ] Rollback tested or confirmed available
- [ ] Public smoke test passed
- [ ] Monitoring window completed

## Today’s next action

Complete Phase 1. Do not create Green until the current Blue backend version,
current Render deploy, intended release commit, and database snapshot decision
have been recorded.

## Active release log

### Release: 2026-08-01 — testing environment update

| Item | Recorded value |
| --- | --- |
| Release commit | Pending |
| Blue EB application | `reproot-backend` |
| Blue EB environment | `reproot-testing-api` |
| Blue EB environment ID | `e-pfizc3hcvp` |
| Blue EB version | `reproot-backend-7ae9204` |
| Blue platform | Python 3.13 / 64-bit Amazon Linux 2023 / 4.13.4 |
| Blue environment URL | `reproot-testing-api.us-east-1.elasticbeanstalk.com` |
| Blue instance type | `t3.micro` (confirmed from the earlier instance-health check) |
| Blue health before release | Warning: 94% memory in use |
| Green EB environment | `reproot-testing-api-green` |
| Green EB environment ID | `e-ze3mkzgqxz` |
| Green EC2 instance observed during creation | `i-0d2bd5c77695c36bf` |
| Green EC2 security group | `sg-05e68dfeb7b9f680c` |
| Blue EC2 security group allowed by RDS | `sg-096d427c0155f815c` |
| RDS security group | `reproot-testing-db-sg` / `sg-0071fbf80b12eaa6d` |
| Green EB version initially cloned | `reproot-backend-7ae9204` |
| Green EB running version after update | `reproot-backend-green-20260801-01` |
| New Green backend artifact | `reproot-backend-green-20260801-01.zip` |
| New artifact SHA-256 | `DBDEB403AD17331B6542540E0493B3B18A16F952EDAA9CCE576D43C080C8E112` |
| Green initial health | Recovered to Ok after authorizing Green in the RDS security group |
| Green post-release instance health | Ok / Green; no causes reported |
| Green observed CPU after release | 0.1% user, 0.1% system, 99.9% idle |
| Production Render service/deploy | Pending |
| Staging Render service/deploy | Pending |
| RDS snapshot identifier | Pending or documented deferral |
| Database strategy | Pending: isolated staging / shared compatibility test |
| S3 strategy | Pending: isolated / shared with restrictions |
| Public switch time | Pending |
| Rollback window closes | Pending |
| Final result | In progress |

#### Questions and decisions

- The Blue environment reported 94% memory usage on its `t3.micro` instance.
- Decision: leave Blue unchanged while Green is prepared.
- Green will deploy the updated Procfile with two Gunicorn workers, two threads,
  and request recycling. Compare Green memory after deployment before deciding
  whether to change the instance type.
- The frontend rollback point is Render service `reproot-web`, branch `Test`,
  successful commit `a031c58` ("Correct Render API origin configuration"),
  deployed July 28, 2026 at 10:25 AM.
- Before cloning, CloudFormation showed stack operation status
  `UPDATE_COMPLETE`. This confirms the most recent stack update completed, but
  it does not confirm drift status. Drift must be detected separately and
  should report `IN_SYNC` before cloning, or any `DRIFTED` resources must be
  reviewed and intentionally handled.
- CloudFormation drift detection for Blue completed with `IN_SYNC` on
  2026-08-01. The clone may proceed from the recorded stack configuration.
- The local repository is on branch `Test` at base commit `486c5a5`
  ("Complete RepRoot workflows legal consent and cookie controls"). The intended
  release also contains tracked, uncommitted changes, so this base commit must
  not be deployed as the new release. Validate and commit the complete intended
  state before building Green or the staging frontend.
- Release decision from the owner: the currently deployed frontend is newer
  than the currently deployed backend, but its changes are considered backward
  compatible with the existing backend. Proceed with the Green backend release
  independently; do not redeploy or switch the frontend during the backend
  Green-to-Blue operation unless validation identifies a dependency.
- The frontend remains the separate Render Static Site `reproot-web`. No
  frontend files or Render deploys are changed by the Elastic Beanstalk
  Blue/Green backend swap. The existing browser application continues calling
  `https://api.rep-root.com`; CloudFront's origin configuration must therefore
  be confirmed to use the swappable Blue Elastic Beanstalk CNAME before the
  backend URL swap.
- CloudFront origin was manually confirmed as
  `reproot-testing-api.us-east-1.elasticbeanstalk.com`. Therefore swapping the
  Elastic Beanstalk environment CNAMEs will move the existing public API path to
  Green without changing the Render frontend or the CloudFront distribution.

#### Problems and resolutions

- **2026-08-01 — Blue memory warning:** Existing backend reports 94% memory in
  use. This is a capacity warning, not evidence of a security incident. The
  planned first mitigation is the already-prepared Gunicorn worker reduction in
  Green. If sustained memory remains high after validation, evaluate upgrading
  Green to `t3.small` before the public switch.
- **2026-08-01 — No immutable release identity yet:** The current intended
  release is not represented by a single Git commit. Green creation may proceed
  only as empty infrastructure, but application deployment and staging frontend
  validation must wait until the intended source has passed local validation
  and has been committed. This prevents the backend ZIP and Render frontend from
  accidentally being built from different code.
- **2026-08-01 — Coordinated-commit exception accepted:** The owner confirmed
  that the already-live frontend and the planned backend do not have a breaking
  dependency. This release will update the backend through Green first and keep
  the current Render frontend unchanged. The backend artifact/version label
  must still be recorded before deployment so it can be rolled back.
- **2026-08-01 — Green clone could not reach PostgreSQL:** Elastic Beanstalk
  created environment `reproot-testing-api-green` and EC2 instance
  `i-0d2bd5c77695c36bf`, but the cloned application version failed during its
  predeploy migration hook with `django.db.utils.OperationalError: connection
  timeout expired`. This means the connection did not reach RDS; it is
  different from a PostgreSQL password-authentication error. Expected cause:
  Green received a new EC2 security group that is not yet an allowed source in
  the RDS security group's PostgreSQL inbound rules. Preserve the existing Blue
  rule and add a separate PostgreSQL/TCP 5432 rule whose source is Green's EC2
  security group. Confirm both resources use the same VPC, then redeploy the
  existing application version to validate the clone before uploading new code.
  Green's EC2 security group was identified as `sg-05e68dfeb7b9f680c`.
- During the RDS-rule step, the source field displayed `0.0.0.0/0`. Do not use
  that value for Green: it permits connection attempts from every IPv4 address.
  The new PostgreSQL rule must use Green's security group
  `sg-05e68dfeb7b9f680c` as its source. Do not remove an existing public rule
  until explicit Blue and Green security-group rules have been verified, so the
  live backend is not disconnected accidentally.
- The Green EC2 web security group itself has inbound HTTP/TCP port 80 from
  `0.0.0.0/0` and outbound all traffic to `0.0.0.0/0`. These are not the RDS
  PostgreSQL rule and should not be replaced during database authorization.
  Navigate through RDS > database > Connectivity & security > VPC security
  groups, then edit that RDS security group's inbound rules. The correct screen
  for this change must show or allow a PostgreSQL/TCP port 5432 rule.
- RDS security-group verification completed: inbound access includes the Blue
  EC2 security group `sg-096d427c0155f815c`, the Green EC2 security group
  `sg-05e68dfeb7b9f680c`, and the existing administrator IP `/32` rule. The
  `0.0.0.0/0` entry shown for the RDS group is outbound, not inbound. Both Blue
  and Green can therefore retain database connectivity during the deployment.
- The existing backend version `reproot-backend-7ae9204` was redeployed to
  Green after the RDS rule was added. Green reached health `Ok`, confirming the
  cloned application can start and connect to the database. The next checkpoint
  is a direct request to Green's `/api/health/` endpoint before any new backend
  artifact is uploaded.
- Green's first direct `/api/health/` request returned HTTP 400. Because the
  environment is healthy and the request reached Django, the expected cause is
  that Green's new Elastic Beanstalk hostname is absent from
  `DJANGO_ALLOWED_HOSTS`. Manually append
  `reproot-testing-api-green.us-east-1.elasticbeanstalk.com` to that protected
  environment property in Green only, preserving every existing hostname. Use
  a hostname only: no scheme, port, path, or trailing slash. Apply the
  configuration and repeat the direct health check. The temporary Elastic
  Beanstalk URL uses HTTP and may display "Not secure"; production TLS remains
  on the public API domain and does not need to be duplicated for this temporary
  validation hostname.
- After changing Green's allowed-host configuration, a subsequent browser test
  temporarily returned `ERR_CONNECTION_TIMED_OUT`. This is not the same as the
  earlier HTTP 400: HTTP 400 proves the request reached Django, while a timeout
  means no HTTP response was received. Because Elastic Beanstalk restarts or
  updates instances when environment properties are applied, first wait for the
  environment operation to finish and confirm `Ready/Ok`. Do not change
  networking during an in-progress update. If the timeout remains after Green
  is fully Ready, review the latest environment events and instance health
  before modifying security groups.
- Green's `DJANGO_ALLOWED_HOSTS` configuration was manually confirmed to include
  both Elastic Beanstalk environment hostnames, `api.rep-root.com`, and
  `operate.rep-root.com`. The comma-separated format is correct and covers the
  future CNAME swap. No further host-list change is required for the direct
  Green health check.
- Browser comparison showed `https://api.rep-root.com/api/health/` returning
  `{"status":"ok"}`, while both raw Blue and raw Green Elastic Beanstalk HTTP
  hostnames timed out. This establishes that the production CloudFront/API path
  and Blue application are healthy, and that direct raw-environment reachability
  is a separate network-path issue. Do not alter Django host configuration based
  on this timeout; verify raw DNS/HTTP reachability and Green health separately.
- CloudShell confirmed the raw Green HTTP endpoint is reachable and returns
  `HTTP/1.1 301 Moved Permanently` with a Location pointing to the HTTPS form of
  the same Elastic Beanstalk hostname. This explains both raw-environment browser
  timeouts: Django's production SSL redirect is working, but the single-instance
  Elastic Beanstalk hostname has no HTTPS listener/certificate. The public API
  works because CloudFront provides HTTPS in front of Blue. Do not disable
  `SECURE_SSL_REDIRECT` in production merely to make the raw hostname browsable.
  For a non-mutating Green health test, call the HTTP origin from CloudShell with
  `X-Forwarded-Proto: https`, matching the secure-proxy signal supplied by the
  production edge. Full browser-based Green testing will require a temporary
  HTTPS edge/domain in front of Green or another deliberately secured staging
  access path.
- Green health validation passed from CloudShell using the secure-proxy header:
  the endpoint returned `HTTP/1.1 200 OK` and `{"status": "ok"}`. Response
  headers included the expected security headers, including HSTS, frame denial,
  content-type protection, and same-origin policies. This confirms the cloned
  application, nginx/Gunicorn path, Django, and RDS connectivity are working.
- The new backend source bundle was created at
  `deploy_artifacts/reproot-backend-green-20260801-01.zip`. It contains 146
  archive entries, uses Linux-compatible paths, includes `Procfile`,
  `requirements.txt`, and `.platform/hooks/predeploy/01_django_setup.sh`, and
  contains zero filenames matching the deployment exclusion rules for
  environment files, credentials, keys, logs, caches, local databases, SQL
  setup, scripts, or documentation. Python compilation completed successfully
  and no tracked migration file is changed relative to the current Git base.
  Artifact SHA-256:
  `DBDEB403AD17331B6542540E0493B3B18A16F952EDAA9CCE576D43C080C8E112`.
- Elastic Beanstalk deployed `reproot-backend-green-20260801-01` to Green and
  the environment returned to health `Ok`. No public URL swap has occurred.
  Before switching traffic, repeat the secure-proxy health test and record
  Green instance memory after the new two-worker Gunicorn process has settled.
- The post-deployment secure-proxy health test for
  `reproot-backend-green-20260801-01` passed with HTTP 200 and status `ok`.
  Green is application-ready pending instance-health/memory review and the
  final pre-swap checklist.
- Post-deployment enhanced instance health reported `Ok`, color `Green`, no
  causes, and the correct deployment version. CPU was effectively idle and the
  prior 94% memory warning did not recur in the health report. The two-worker
  Gunicorn mitigation is accepted for this release; continue monitoring after
  the public switch before deciding whether a RAM upgrade is necessary.
- A log bundle supplied after a post-login error was identified as an old Blue
  bundle, not current Green logs: it referenced environment stack
  `e-pfizc3hcvp`, private instance IP `172.31.26.213`, dates from July 28, and
  three Gunicorn workers. It cannot establish the cause of a current Green
  post-login error. Always confirm the environment ID and timestamps when
  collecting deployment diagnostics.
- The old bundle nevertheless contains a separate SMTP exception:
  `SMTPAuthenticationError: 525 5.7.1 Unauthorized IP address`. SMTP
  credentials were accepted far enough for the provider to apply an IP policy,
  but the sending instance IP was not authorized. For Green, authorize its
  current public Elastic IP `54.163.254.26` in the SMTP provider's trusted-IP
  control if that provider requires IP allowlisting. Do not place credentials
  or provider secrets in this runbook. A rebuilt/replaced single-instance
  environment may receive a new public IP, so recheck this after infrastructure
  replacement or adopt a fixed-egress design later.
- Current Green access logs confirmed that authentication and database access
  are working: professional login and profile-status requests returned HTTP
  200. Immediately afterward, authenticated dashboard endpoints consistently
  returned HTTP 403 with the legal-version permission response. Green applied
  migrations `0033` through `0040`, including legal acceptance, while the live
  Render frontend remained on its July 28 deployment. This is a release-version
  mismatch: the new backend requires the current legal consent workflow, but
  the old live frontend does not complete that workflow correctly. It is not
  evidence of missing secrets or a failed database migration. Deploy and test
  the matching current frontend before judging the Green backend or swapping
  production traffic.
