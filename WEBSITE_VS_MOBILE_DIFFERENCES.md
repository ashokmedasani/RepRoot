# Website vs Mobile Flutter — Differences to Discuss

**Created:** 2026-08-03
**Purpose:** The website (Angular) is live for friend-testing and must not be changed right now. This document collects every known difference, gap, or potential future issue between the website and the mobile Flutter app — plus items inside each platform worth fixing later. Review this after testing feedback comes in, and fix items from here deliberately, one by one.

**Rule of thumb used everywhere:** the backend is the single source of truth. Both frontends render plan limits, legal versions, and lock state live from the API — a change in `backend/.env` (or `backend/config/settings.py` defaults) flows to both platforms with zero frontend/mobile code changes.

---

## 1. Deliberate mobile additions (working as intended, just different from web)

- **"Not now — sign out" on both legal consent screens.** The web has no such button because a browser user can simply navigate away; a mobile gate with no exit would trap the user in the app. This clears the local session only — it never touches server state. Keep unless you want strict web parity.
- **Bottom navigation is icon-only with a raised active bubble** (the design you approved from the Figma reference), whereas the web uses side/top navigation. Intentional.
- **Mobile lists show fewer columns than the web tables** (mobile width limit). The full column-by-column comparison of every table lives in `mobile_flutter/Mobile_Flutter_Updates_Required_2026-08-03.md` — several tables still render only 2–3 of the web's 6–8 columns and four render none. Decide per-table which fields matter on mobile.

## 2. Real gaps in the mobile app — ALL BUILT on 2026-08-03 (pending device testing)

Every item below is now implemented on mobile, tracing the real Angular/backend contracts. Test each on a device:

- ~~Form Request Detail~~ — bottom sheet shows every submitted answer (with lead-form labels) before Approve/Reject, plus the create-client form (group picker, username, password + generate, email-credentials toggle).
- ~~Change-request diff view~~ — Field / Current / Requested rows, unchanged fields dropped, optional review note, matching the web logic.
- ~~Schedule~~ — meeting booking (incl. group sessions), hand-built month calendar (busy-shading, meeting dots, days-off strikethrough, tap-to-filter), date-offs + weekday-offs management, accept/decline of client requests. Duration is a 15/30 segmented control (backend hard-rejects other values). Bug fixed along the way: reschedule was sending naive local time, now UTC ISO.
- ~~Client meeting request~~ — request sheet with date, 15/30 length, title, notes, slot chips from availability; shows "professional has not added availability" hint and pending-approval labels.
- ~~Group CSV import~~ — 3-step wizard (upload → column-mapping preview with match-confidence pills → confirm), then both result lists (created with temp passwords / failed with per-row reasons). Web has no template download, so mobile shows expected column names with copy/share.
- ~~Manual client create~~ — now renders the selected group's real registration form dynamically (dropdowns, date pickers, long-text, required markers), same payload as web. Groups without a registration form are filtered out, as on web.
- ~~Client payment proof upload~~ — attach/replace/remove JPG/PNG/WEBP/PDF (5MB client-side check), "View attachment" downloads the authenticated file and opens the share sheet. Bug fixed: mobile wrongly required transaction reference; backend accepts reference OR file.
- Public web-only funnels (public lead form, public group registration) — left web-only deliberately, confirm that's the intent.

Small known non-parities remaining (deliberate, low priority): web's registration-submission prefill (`?registrationSubmissionId=`) and 3-way portal-access mode in client create have no mobile equivalent; schedule shows device-local times instead of the web's timezone re-labelling.

## 3. Known small inconsistencies (either platform, low risk, fix when convenient)

- **`subcategories_per_category` and `templates` limits are enforced by the backend but not displayed on the plan comparison cards — on either platform.** Mobile deliberately matches the web's display (gaps included) so they don't drift. If you want them shown, add to both at once.
- **Stale comment in `backend/config/settings.py` (~line 320-323):** says Premium storage is "50x" Free / "5x Pro"; actual values are 100x / 10x (10 GB). Comment only, no functional impact.
- **Plan-lock reorder has no freeze gate.** The deprecated design doc said reordering should freeze once a downgrade takes effect; the real endpoint (`reorder_active_items`) has no time gate on either platform. Decide if you still want the freeze; if yes it's a backend change that both platforms inherit automatically.
- **No "N clients affected / unassign all" UI for a locked resource shared via template assignment** — on either platform; locked resources are silently dropped from assignments instead. From the deprecated design doc; decide whether to build it.
- **Manual client reactivation vs plan lock:** `ClientAccessStatusView` flips `is_active` but never clears `suspended_by_plan_lock`, so a manually-reactivated client in a still-locked group gets silently re-suspended on the next cascade sync. Arguably correct, but there's no message telling the professional why.
- **Legal-403 detection is string matching, in three places.** The backend 403 body says "…Terms & Conditions and Privacy Notice must be accepted…", and BOTH the web (`error.interceptor.ts`) and mobile (`api_client.dart`) detect re-consent by matching that substring. If that backend sentence is ever reworded, both interceptors silently stop redirecting. Future fix: have the backend add a machine-readable code (e.g. `{"code": "legal_reconsent_required"}`) and match on that — backend + 2 small frontend changes.

## 4. Mobile items needing a build-time setting

- **Legal document links point to the website.** The Terms/Privacy text lives only as web pages (single source — this is good), and mobile opens them via the browser. The URL defaults to `https://rep-root.com`; if the site lives elsewhere, build the APK with `--dart-define=WEB_APP_URL=https://your-real-domain`.
- **API base URL** similarly comes from `--dart-define=API_BASE_URL` (defaults to the Android emulator loopback for dev). **This is almost certainly the cause of a reported sign-in timeout on a real device** — `10.0.2.2` only resolves on the Android emulator; a physical phone needs `--dart-define=API_BASE_URL=http://<your-computer's-LAN-IP>:8000` (both devices on the same Wi-Fi), or a real hosted backend URL.
- **Google Sign-In** (professional-only, added 2026-08-03) needs `--dart-define=GOOGLE_SERVER_CLIENT_ID=<same value as backend's GOOGLE_OAUTH_CLIENT_ID>`. Without it the button hides itself automatically (`GoogleAuthService.isConfigured`). This also needs one-time setup only you can do — see the note below.

## 5. Payments (deferred by you — waiting on Razorpay support)

- Provider is Razorpay; `REPROOT_PAYMENTS_ENABLED` currently defaults to `False` in settings, and billing runs in test mode (plan changes apply instantly, no charge).
- The approved plan policy is recorded only in `Documentation/PLAN_AND_BILLING_DRAFT.md`. The backend catalogue still requires the separately approved implementation pass; do not copy prices from older reports or historical code notes.
- Mobile opens checkout/billing-portal URLs in the external browser — same flow as web. Nothing mobile-specific should need to change when you finish the Razorpay configuration; it's all backend config.
- When you enable payments for real: re-test the upgrade dialog, cancellation scheduling, and the "cancellation blocked at >100% Free storage" path on both platforms.

## 6. Not yet verified on a real device (code is written, compile passed, runtime untested)

- **Google Sign-In/Sign-Up (professional).** Added 2026-08-03, mirrors the real Angular flow 1:1 (same `/professional/auth/google/` endpoint, same accept_terms/accept_privacy contract, same "existing account → please sign in" branch on signup). Cannot be tested yet — needs one-time Google Cloud Console setup that only you can do, since it requires your app's release/debug signing SHA-1 fingerprint:
  1. In the Google Cloud project that already owns `GOOGLE_OAUTH_CLIENT_ID` (the same variable the web app's `APP_CONFIG.googleClientId` uses — see `backend/config/settings.py`), open **APIs & Services → Credentials**.
  2. Create a new OAuth client of type **Android**, package name `com.reproot.flutter`, and the SHA-1 from `cd android && ./gradlew signingReport` (use the `debug` SHA-1 for testing; add the `release` one later when you sign a real build).
  3. No new client ID needs to go in mobile code for this Android client — Google's SDK reads it automatically from the package name + SHA-1 you just registered. The only value mobile needs is the **existing web client ID**, passed as `serverClientId` so the returned ID token's `aud` matches what the backend already checks: build/run with `--dart-define=GOOGLE_SERVER_CLIENT_ID=<that same GOOGLE_OAUTH_CLIENT_ID value>`.
  4. `flutter pub get` to fetch the new `google_sign_in: ^7.2.0` dependency, then test the button on both login and signup.
- Nested drag-reorder in the resources page (resources inside an expanded category) — drag auto-scroll is limited in nested shrink-wrapped lists; check the feel.
- The new mid-session legal-403 redirect (change the legal version in `.env` while a mobile session is open, then perform any action — the app should land on the consent screen).
- Professional signup end-to-end (a real bug was fixed: the app previously never sent `accept_terms`/`accept_privacy`, so signup 400'd).
- Forgot-password full flow against a live backend (OTP email delivery, resend countdown, error branches).
- Legal consent first-login and re-consent flows for both roles.

## 7. Testing-phase reminders

- The two old planning docs are quarantined in `_deprecated_docs/` and must not be used as reference (rule added to AGENTS.md). This document supersedes them for "what differs / what's pending".
- `mobile_flutter/CLEANUP_NOTES.md` tracks temporary files to delete later (design previews, the old coachflow .iml, audit docs) once their purpose is served.
