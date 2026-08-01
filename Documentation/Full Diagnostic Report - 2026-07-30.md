# RepRoot Studio — Full Diagnostic Report
**Date:** 2026-07-30
**Scope:** Django backend, Angular frontend, Flutter mobile app (spot-checked). Read-only investigation — nothing in this report has been fixed yet unless explicitly marked "already fixed."

---

## 1. Executive Summary

Baseline health (compile, Django system check, migrations) is clean. The plan-limit lock system, storage quotas, and cancellation flow audited in prior sessions remain solid. Cross-tenant data isolation was audited in depth this round and came back clean — no professional can reach another professional's data, and no client can reach another client's data under the same professional.

The real gaps are elsewhere: nobody gets notified when the app throws an error (it's logged, not alerted), there is no actual database backup strategy in this codebase, Razorpay checkout is not yet testable end-to-end (missing webhook secret + no public webhook URL), payment checkout has no rate limiting despite settings implying it does, and the Terms/Privacy pages are a placeholder template that doesn't name the real payment processor or list real sub-processors.

None of this was fixed as part of this report — per your instruction, this is findings only.

---

## 2. Baseline Health Check

- `python manage.py check` — **0 issues.**
- `python manage.py makemigrations --check --dry-run` — **no changes detected** (no pending model changes). The connection warning shown is only the sandbox's lack of a reachable Postgres instance, not an app problem — same known limitation as prior sessions.
- `tsc --noEmit` on the frontend — clean on the most recent subscription-payment edits (already verified earlier this session).

---

## 3. Razorpay Billing — Current Test Status

You asked for this included even though you already know it's unfinished. Full detail:

**What's already fixed/working:**
- `RAZORPAY_BASE_URL` corrected (was building a broken double-path URL).
- `REPROOT_BILLING_TEST_MODE=False` is set in your real `.env`, so checkout no longer takes the "instant apply, no gateway" shortcut — it now genuinely attempts a real Razorpay payment-link creation.
- Webhook signature verification is implemented correctly (HMAC-SHA256, constant-time compare).
- Webhook payload processing correctly dedupes repeat deliveries by `payment_id`, and applies the plan change + writes a ledger entry.
- Pricing is looked up server-side from a fixed dict (`PLAN_PRICES`), not trusted from the client — the checkout amount can't be tampered with from the frontend.

**What's still blocking a real end-to-end test:**
1. **`RAZORPAY_WEBHOOK_SECRET` is still the placeholder `test123`** in your `.env`. You need the real value generated when you configure a webhook in Razorpay's Test Mode dashboard.
2. **The webhook endpoint (`/api/accounts/billing/razorpay/webhook/`) isn't reachable from the internet.** Razorpay calls this server-to-server to confirm payment; it cannot reach `localhost`. The browser-side redirect after payment works fine locally, but the actual plan upgrade only happens when the webhook fires — without a public URL (e.g. an ngrok tunnel or a staging deploy) registered in Razorpay's dashboard with the matching secret from #1, you can complete a test payment in Razorpay's UI and your account will never actually upgrade.
3. Once #1 and #2 are done, the flow should work end-to-end as coded.

**Newly found this round (see Section 5.3 for full detail), not yet fixed:**
- Checkout/payment-link creation has no rate limiting wired up, despite a `THROTTLE_PAYMENTS_RATE` setting existing (it's defined but never attached to the checkout view).
- The webhook's two database writes (plan upgrade + ledger entry) aren't wrapped in one atomic transaction — a failure between them could leave a paid account with no financial record, or vice versa.
- A raw `json.loads()` on the webhook body has no error handling — malformed-but-signed content would 500 instead of failing gracefully.
- If a professional starts checkout but never pays, the payment-link ID stays on their profile forever with nothing to expire or clean it up.
- No fraud/velocity checks beyond the server-side price lookup (expected at this stage, just noting the gap).

---

## 4. Security — Secret Exposure & Cross-Tenant Data Isolation

### Secret / credential exposure
- **No hardcoded secrets found** in frontend or mobile code (checked for Stripe/Razorpay secret keys, AWS keys, Django secret key material). The public app config (`app-config.js`) only exposes `apiBaseUrl`, `supportEmail`, and a Google OAuth *client ID* — all intentionally public.
- **Razorpay/Stripe secret keys never reach the browser.** Confirmed the billing status/checkout API responses only ever include plan names, booleans, prices, and currency — never `RAZORPAY_KEY_SECRET` or `RAZORPAY_WEBHOOK_SECRET`.
- **Medium finding:** the professional's login token is stored in browser `localStorage` (used across most of the professional-side API services). This is standard for many web apps, but it means that if the site ever had an XSS bug, a stolen token would persist indefinitely (not scoped to the browser tab, doesn't expire on tab close). The client portal and admin portal already use the safer `sessionStorage` — worth eventually aligning the professional side to match, or moving to an httpOnly cookie.
- **Low finding:** Django admin lives at the default `/admin/` path with no extra restriction (no IP allowlist, no 2FA, no renamed path). Low cost to add, standard hardening.
- Mobile app already does this right — uses encrypted OS-level secure storage (Keychain/Keystore), not plaintext.
- `backend/.env` is confirmed git-ignored and not committed. Production security settings (HSTS, secure cookies, SSL redirect, required S3 + real email backend) are all properly enforced when `DEBUG=False`.

### Cross-tenant data isolation (can one user see another's data?)
This was checked in depth across every object-fetching endpoint (clients, groups, resources, templates, chat, tracking entries, reminders, payment requests, scheduling) on both the professional side and the client side.

**Result: no gaps found.** Every endpoint that fetches something by ID scopes the query to the requesting professional's own data, or to the authenticated client's own record — never trusts a bare ID from the URL/body without an ownership filter. Passing another professional's client/group/resource ID returns a plain "not found," not a leak. A client cannot see another client's chat, tracking entries, payment requests, or meetings under the same professional — each client-portal endpoint derives its scope from the authenticated client's own token, never from a caller-supplied identifier. Every view also has an explicit permission class (nothing was left open to unauthenticated/unrelated access by omission).

This is good news — the two things you were most worried about (secrets leaking, and one client/professional reaching another's data) both check out clean.

---

## 5. Operations — Error Tracking, Backups, Payment Resilience

### 5.1 Error tracking — "will I hear about bugs before users complain?"
**Short answer: not automatically, no.**

There's no third-party error-tracking tool (no Sentry or equivalent). But it's not nothing — there's a custom in-house system already built: every backend crash gets automatically captured into an internal error log table, and the frontend has a global error handler that reports JavaScript errors to the backend the same way. All of this is visible in the Admin Portal's Errors page.

The gap: nothing pushes that information to a person. No email, no Slack message, no notification — someone has to manually open the Admin Portal and check. In practice, that means a user reporting a bug is still the most reliable way anyone finds out today, even though the underlying capture pipeline already exists and just needs an alert wired to it (e.g. email yourself when a new error log is created).

### 5.2 Backups — "if something goes wrong, can I restore?"
**Short answer: there is no backup system in this codebase today.**

Postgres runs with a normal data volume and nothing takes scheduled dumps or snapshots — not in a management command, not in CI, not in any deployment config. The only "snapshot"-like thing that exists is the Recycle Bin feature, and that is a different thing: it only protects one soft-deleted record for about 14 days, in case someone deletes a client or resource by mistake. It does nothing for database corruption, a bad migration, an accidental mass-delete, or a server/provider failure. Uploaded files (resources, chat images, profile photos) also have no versioning or backup configured on the storage bucket.

Practically: whatever protection exists today comes entirely from your hosting/database provider's own automatic backups, if any — nothing in the app guarantees or documents that. Worth confirming directly with whichever provider you deploy Postgres and file storage to, and writing down what their retention/restore process actually is.

### 5.3 Payment resilience & fraud
Already summarized above in Section 3's "newly found" list — repeating the key points briefly here for completeness: webhook signature verification and dedupe both work correctly; pricing is server-side and can't be tampered with; but checkout has no rate limiting wired up despite a throttle setting existing for it, the two database writes on a successful payment aren't wrapped in one atomic transaction (so a failure partway could upgrade a plan with no matching financial record), and there's no cleanup for payment links that are created but never paid.

---

## 6. Unused / Orphaned Data ("scraps")

Per your instruction, nothing below has been changed — this is a list for you to decide on.

- **No stray backup files** anywhere (no `.bak`/`.old`/`.tmp`/duplicate-suffixed files).
- **No genuine dead commented-out code** — the only large comment blocks found are legitimate design-rationale documentation, not disabled code.
- **Leftover "Reference" naming from the Resource rename:** the backend was fully renamed, but the frontend still has a `professional-references` component directory/class and a shared `references-accordion` component still in active use under their old names (the user-facing text was updated to "Resource Library," the code wasn't). Also two media upload folders on disk (`professional-references/`, `trainer-profiles/`) still use pre-rename names. Not urgent, but worth a follow-up rename pass.
- **`@angular/animations` package appears unused** — zero imports found anywhere in the frontend. Worth confirming and possibly removing.
- **Stripe integration is legacy, not fully dead:** new signups can't create a Stripe subscription anymore (the code path for that is unreachable), but old accounts that still have a Stripe customer/subscription ID can still hit Stripe for cancellation/billing-portal. It's intentionally kept for backward compatibility, not accidental leftover.
- **`Documentation/backend/` and `Documentation/frontend/` (roughly 150 files) mirror an old, pre-rename folder structure** that no longer matches the actual codebase (references `trainer-login`, `trainer-references`, etc. — folders that don't exist anymore). This entire subtree is stale and should probably be regenerated or archived. Other docs (migration-completion summaries, changelogs, setup guides) are still accurate or intentionally historical.
- **Current git status:** 20 modified tracked files (this session's work) — `backend/.env.example`, `resource_cold_storage.py`, `views.py`, the account-settings/subscription-payment frontend files, plus 14 modified files under `mobile_flutter/windows/` (Windows desktop runner scaffolding, not app code) and one Flutter resources-page file. No untracked files at all — the earlier note about "~15 uncommitted mobile_flutter files" is roughly right, except they're modified, not new/untracked.

---

## 7. Legal — Privacy Policy & Terms of Service

**A Privacy Policy and Terms of Service page do exist**, routed at `/privacy` and `/terms`. However, the page's own text openly states it's a general placeholder template, not legal-counsel-reviewed copy, and tells you to have it reviewed by a lawyer and replace the bracketed placeholders before launch — so this was already flagged as unfinished by whoever wrote it.

Concrete gaps found comparing the policy text against what the app actually does:
- **No specific data retention period is stated** — the real tiered values (60/90/180 days visibility, 180-day hard delete) aren't mentioned at all.
- **The payment processor is never named.** Razorpay isn't mentioned anywhere in the policy, and the backend still has Stripe wired in parallel for legacy accounts — a user has no way to know which company is actually handling their payment.
- **Storage disclosure is vague and slightly misleading** — the Cookies section says only "cookies," but the actual mechanism is a browser localStorage token, not a cookie at all.
- **Sub-processors aren't named** — AWS S3 (file storage), Google Calendar/OAuth, and the email provider are all live, production-required dependencies handling personal or health data, and none of them is disclosed.
- **The checkout page references a "Cancellation Policy" as if it's a separate document** — no such document exists anywhere; it's a dead reference to something that was never written. (The actual cancellation behavior described there is accurate to the code, for what it's worth — just not backed by a real linked policy.)

---

## 8. Priority Punch List

Roughly in the order I'd tackle them:

1. Get real Razorpay test credentials fully wired (webhook secret + a public webhook URL via tunnel/staging) so you can actually test a payment end-to-end.
2. Wire an alert (even just an email to yourself) on new error-log entries, so bugs surface without waiting for a user report.
3. Confirm and document what backup/restore your hosting and database provider actually give you — right now nothing in the app guarantees this.
4. Wrap the webhook's plan-upgrade + ledger-entry writes in one atomic transaction, and attach the existing payment throttle setting to the checkout view.
5. Have the Terms/Privacy pages properly written (payment processor named, sub-processors listed, retention period stated) and reviewed before relying on them for real users.
6. Lower priority: finish the frontend "Reference" → "Resource" rename, drop the unused `@angular/animations` package if confirmed unused, and refresh the stale `Documentation/backend`/`Documentation/frontend` folders.
