# Mobile Flutter — Field-Level Parity Audit vs Angular Studio Web App

**Date:** 2026-08-03
**Scope:** `frontend/src/app/pages/studio/**` (Angular, source of truth) vs `mobile_flutter/lib/features/**` (Dart)
**Method:** Read-only. Every `.html` template and, where columns/fields are defined in TypeScript, the matching `.component.ts`, compared against the corresponding Dart widget. No files were modified. No `.env` or credential files were read.

---

## Summary

**43 pages/screens audited**, walked in real user-journey order starting at the login entry point (Studio has no in-app landing page).

| Status | Count |
| --- | --- |
| **Missing entirely** in Flutter | **11** |
| **Partially built** (page exists, major sub-features absent) | **21** |
| **Built but fields differ** (structure matches, field set diverges) | **9** |
| **Fully matches** | **2** |

The dominant pattern is not missing pages — it is **missing columns and missing secondary workflows inside pages that exist**. Angular routinely renders 6–8 column tables (Clients = 8 columns, Schedules = 7, Form Requests = 7, Group Approved Users = 7, Dashboard Payments = 6, Client Account Requests = 6, Data Entries = 6); Flutter renders the same data as a 3-slot `ListTile` (title / subtitle / trailing). That is a deliberate mobile constraint, but the owner needs to decide *which* 3–5 of the 8 survive, and where the rest go (expandable row, detail sheet, or dropped). Every such table is enumerated below on both sides.

Second-largest theme: **the entire account-recovery and legal-consent surface is absent from Flutter** (forgot password, professional legal consent, client legal consent, signup legal-review dialog with versioned documents). A professional who forgets their password on mobile has no path forward, and neither role can re-accept an updated legal version, which on web is a hard gate.

---

# PART 1 — Entry & Authentication Journey

---

## 1. Portal Access Entry (`/portal`)

- **Angular:** `pages/studio/portal/access-entry-placeholder.component.html` (`AccessEntryPlaceholderComponent`)
- **Flutter:** `lib/features/auth/role_chooser_page.dart` (`RoleChooserPage`, route `/`)
- **Status:** **Built but fields differ**

**Angular elements (full list):**
1. Brand header — "RepRoot Studio" mark + wordmark
2. "Return to Studio" back link
3. Eyebrow "Studio portal", H1 "Choose your access", subtitle
4. Professional card: icon "P", label "Professional", H2 "Professional workspace", description, **two** buttons — "Professional sign in", "Create professional account"
5. Client card: icon "C", label "Client", H2 "Client workspace", description, access note ("Professional-approved access" + "Use the code and credentials supplied by your professional"), **one** button — "Client sign in"
6. Footer: "RepRoot Studio" summary line
7. Footer nav links (8): RepRoot website, Studio overview, Help & Support (mailto), Professional Terms, Professional Privacy, Client Terms, Client Privacy, Cookie Notice
8. Footer safety copy: "Use the access route intended for your account role. Never share passwords or one-time verification codes."

**Flutter elements:**
1. Brand: `assets/icon/icon.png`, "RepRoot", "Professional & Client Management"
2. "CONTINUE AS" label
3. `FilledButton.icon` "Professional" (fitness_center icon)
4. `OutlinedButton.icon` "Client" (person_outline icon)
5. Auto-redirect on stored session (professional → dashboard; client → change-password or dashboard)

**Gap:**
- Missing: "Create professional account" as a distinct entry action (Flutter buries signup inside the login page).
- Missing: client-side access note explaining professional-approved access.
- Missing: **all 8 footer links** — Terms, Privacy (professional + client), Cookie Notice, Help & Support mailto, RepRoot website. This is a legal/app-store exposure: no route to the legal docs anywhere in Flutter.
- Missing: safety copy about never sharing passwords/OTPs.
- Flutter *adds* session auto-redirect (good, keep).

---

## 2. Professional Access Chooser (`/professional-access`)

- **Angular:** `professional/professional-access/professional-access.component.html`
- **Flutter:** none
- **Status:** **Missing entirely** (low priority — functionally folded into the role chooser)

**Angular elements:** Back link to `/portal`; eyebrow "Professional Access"; H1 "Choose Login or Signup"; subtitle; two choice cards — "Login" (icon L, "Enter username or email and password.") and "Signup" (icon S, "Create a professional account with required profile details.").

**Flutter:** none.

**Gap:** Entire page absent. Acceptable to collapse on mobile, but the "Signup" affordance and its explanatory copy should surface somewhere.

---

## 3. Professional Login (`/professional/login`)

- **Angular:** `professional/professional-login/professional-login.component.html` + `.ts`
- **Flutter:** `lib/features/auth/professional_login_page.dart`
- **Status:** **Partially built**

**Angular fields/actions (full list):**
1. Shell eyebrow "Professional portal", title "Login to RepRoot Studio", subtitle
2. Header action: "New to RepRoot Studio?" → "Sign up" link
3. `loginNotice` top banner (session-expired / redirect notice)
4. Field: **Email or Username** (required, `autocomplete="username"`)
5. Field: **Password** (`app-password-input`, show/hide toggle, `autocomplete="current-password"`, required)
6. Link: **"Forgot password?"** → `/professional/forgot-password`
7. Button: "Continue" (disabled while submitting)
8. `loginMessage` inline form message
9. Divider "or" + **Google Sign-In button** (`app-google-signin-button`, variant=login) with `credential` / `unavailable` / `loadError` handlers

**Flutter fields/actions:**
1. AppBar "Professional Login"
2. `AuthBrand` "Welcome back" / "Sign in to your professional workspace"
3. Field: **Username or email** (`AutofillHints.username`)
4. Field: **Password** (`PasswordField`, `AutofillHints.password`)
5. Button "Sign in" (spinner while submitting)
6. TextButton "New professional? Create an account"
7. `FormMessage` error line
8. Post-login profile-status check → routes to profile setup if incomplete

**Gap:**
- **Missing: "Forgot password?" link and the entire recovery flow** (see §5). Highest-severity auth gap.
- **Missing: Google Sign-In** entirely (no button, no divider, no unavailable/load-error handling).
- Missing: `loginNotice` pre-form banner for session expiry / redirect reasons.

---

## 4. Professional Signup (`/professional/signup`)

- **Angular:** `professional/professional-signup/professional-signup.component.html` (171 lines) + `.ts` (636 lines)
- **Flutter:** `lib/features/auth/professional_signup_page.dart`
- **Status:** **Built but fields differ**

**Angular fields/actions (full list):**
1. 3-step progress rail: "1 Account details / Username and email" → "2 Email verification / Six-digit OTP" → "3 Secure and review / Password and legal review"
2. Field: **Username** + inline **"Verify"** button; states: available / taken / failed; `usernameCheckMessage`; **username suggestion chips** (clickable, applies suggestion); `fieldErrors.username`
3. Field: **Email ID** + inline **"Send OTP"** button (label varies); "email already registered" branch with links to sign-in and forgot-password; `emailOtpHelpText`; `emailCheckMessage`; **resend-OTP countdown timer** with "resend OTP enables in Ns" and a resend button; `localDebugOtp` display
4. Field: **OTP** (6-digit, `inputmode=numeric`, `autocomplete=one-time-code`, maxlength 6) + inline **"Verify"** button with success/error styling
5. Field: **Password** (`app-password-input`) + **`app-password-requirements` live checklist**
6. Field: **Confirm Password**
7. Button: "Review and Create Account" (disabled unless requirements met and passwords match)
8. `signupMessage` and `fieldErrors.general`
9. Divider "or" + **Google Sign-Up button**
10. **Legal review modal** — "Account creation · Step 2 of 2"; H2 "Review how RepRoot Studio works"; intro; **"Effective {date} · Version {n}"** line; two document links (Professional Terms, Professional Privacy Notice, each with title + description); consent checkbox; "Back" button; "Accept and Create Account" button (separate handler for the Google path)

**Flutter fields/actions:**
1. AppBar "Create account"; `AuthBrand` "Join RepRoot"
2. Field: **Username** + "Check" button; helper "5-10 characters, letters/numbers/.-"; `_StatusLine` for available/taken
3. Field: **Email** + "Send code" / "Resend" button; `_StatusLine`; dev OTP shown as "Dev code: N"
4. Field: **Verification code** + "Verify" button (shown when status is sent/verifying)
5. Field: **Password** (client-side rule: ≥8 chars + 1 special)
6. Field: **Confirm password**
7. Checkbox: "I agree to the Terms & Conditions and Privacy Policy." (plain text, no links)
8. Button "Create account"; `FormMessage`
9. On success → profile setup

**Gap:**
- Missing: **3-step progress rail**.
- Missing: **username suggestion chips** (Angular offers alternates when taken; Flutter just says taken).
- Missing: **resend-OTP countdown timer** and the "if not received…" affordance — Flutter's Resend has no cooldown UI.
- Missing: **"email already registered" branch** with deep links to sign-in / forgot-password.
- Missing: **live password-requirements checklist** (`app-password-requirements`) — Flutter only validates on submit with one error string.
- Missing: **Google Sign-Up**.
- Missing: **the full legal review modal** — document version, effective date, tappable Terms link, tappable Privacy link, per-document descriptions. Flutter's checkbox is unlinked text, so consent is not evidenced against a document version.

---

## 5. Professional Forgot Password (`/professional/forgot-password`)

- **Angular:** `professional/professional-forgot-password/professional-forgot-password.component.html` (92 lines) + `.ts` (375 lines)
- **Flutter:** **none** (no file, no route in `app/router.dart`)
- **Status:** **Missing entirely** — highest priority gap

**Angular fields/actions (full list):**
1. 3-step progress rail: "1 Email" → "2 Verify OTP" → "3 New password"
2. Field: **Email ID** + inline **"Send OTP"** button; read-only once verified
3. `resetFieldErrors.email`
4. **"No professional account found"** branch with links to Sign up and Login
5. `resetOtpHelpText` / `resetOtpMessage` states (idle / sent / failed / verified)
6. **Resend countdown**: "resend OTP enables in Ns" then a "resend OTP" text button
7. Field: **OTP** (6-digit, numeric, one-time-code) + inline **"Verify"** button with success/error styling; `resetFieldErrors.otp`
8. Field: **New Password** + **`app-password-requirements` checklist**; `resetFieldErrors.password`
9. Field: **Confirm Password**; `resetFieldErrors.confirmPassword`
10. Button: "Reset Password" (gated on requirements met + match)
11. `resetMessage` and `resetFieldErrors.general`
12. Header action: "Remembered it?" → "Login"

**Flutter:** none.

**Gap:** **Entire flow missing.** A professional locked out of the mobile app cannot recover their account without going to the web app. All 12 elements above need building: 3-step rail, email + send-OTP, account-not-found branch, resend countdown, OTP verify, new password + requirements checklist, confirm password, submit, and the four distinct error slots.

---

## 6. Professional Profile Setup (`/professional/profile-setup`) — required first-login step

- **Angular:** `professional/professional-profile-setup/professional-profile-setup.component.html` (192 lines) + `.ts` (169 lines)
- **Flutter:** `lib/features/auth/professional_profile_setup_page.dart`
- **Status:** **Built but fields differ**

**Angular fields (full list, 12 inputs):**
1. Eyebrow "Required first login step"; H1; warning copy ("may take around 10-15 minutes")
2. **Profile photo** — frame with preview or initial placeholder, filename display, "Upload photo" / "Change photo" button, file input `accept="image/*"`
3. **First name** * (`autocomplete=given-name`)
4. **Middle name** (Optional, `autocomplete=additional-name`)
5. **Last name** * (`autocomplete=family-name`)
6. **Professional code** * — with **help tooltip bubble** explaining clients log in with this code; placeholder "e.g. FITJOHN"; live availability check on input with three states (invalid / available / taken) plus default hint
7. **Gender** * — `<select>` from `genders` list
8. **Birth month** * — `<select>` from `months` (value/label pairs)
9. **Birth year** * — `<select>` from computed `years`
10. **Country** * — `<select>` from **`countries` list (ISO codes)**
11. **State / Region** * — `<select>` from **`stateOptions`, dependent on selected country**
12. **Professional headline** (Optional, maxlength 180)
13. **About me** (Optional, textarea rows=5)
14. Button "Save and continue" / "Saving profile..."; loading state "Loading your professional details..."; `setupMessage` error

**Flutter fields:**
1. AppBar "Finish your profile"; `AuthBrand` "Almost there"
2. **Profile photo** — CircleAvatar; **Camera** button, **Gallery/Replace** button, **Remove** button; helper "Optional · JPG, PNG, or supported phone image · maximum 5 MB"; 5 MB client-side size check
3. **First name**
4. **Middle name (optional)**
5. **Last name**
6. **Professional code** + "Check" button; helper "Clients type this to reach you"; availability message
7. **Gender** — Dropdown (`Male / Female / Other / Prefer not to say`)
8. **Birth month** — Dropdown (12 month names)
9. **Birth year** — Dropdown (age 18+ down 83 years)
10. **Country** — **free-text `TextField`**
11. **State** — **free-text `TextField`**
12. Button "Save and continue"; multipart PUT with `professional_id, first_name, middle_name, last_name, gender, country, state, birth_month, birth_year, profile_photo`

**Gap:**
- **Missing field: Professional headline** (maxlength 180) — not sent in the Flutter multipart payload at all.
- **Missing field: About me** (textarea) — not sent either.
- **Country / State are free-text on Flutter vs ISO-backed dropdowns with country→state dependency on Angular.** This will produce dirty, unmatchable location data.
- Missing: professional-code **help tooltip** explaining why the code matters.
- Missing: the "10-15 minutes" expectation-setting warning.
- Flutter *adds* camera capture and a 5 MB guard (both good — Angular has neither).

---

## 7. Professional Legal Consent (`/professional/legal-consent`)

- **Angular:** `professional/professional-legal-consent/professional-legal-consent.component.html`
- **Flutter:** **none**
- **Status:** **Missing entirely**

**Angular elements (full list):** brand topbar + "Professional access" badge; eyebrow "Updated legal documents"; H1 "Review before continuing"; explanatory copy about a new published version; **"Effective {legalEffectiveDate} · Version {legalVersion}"**; two document links with titles and descriptions — *Professional Terms & Conditions* ("Account, client-data, payment, and platform responsibilities.") and *Professional Privacy Notice* ("How professional and client information is processed."); **consent checkbox**; error message slot; "Accept and Continue" / "Saving..." button gated on the checkbox.

**Flutter:** none.

**Gap:** Entire re-consent gate missing. On web this blocks the professional until they accept a newly published version; on mobile there is no equivalent, so a professional can keep operating on a stale legal acceptance.

---

## 8. Client Login (`/client/login`)

- **Angular:** `client/client-login/client-login.component.html` (97 lines) + `.ts` (143 lines)
- **Flutter:** `lib/features/auth/client_login_page.dart`
- **Status:** **Built but fields differ**

**Angular fields/actions (full list):**
1. Shell eyebrow "Client Portal", title, subtitle; header action "Professional workspace?" → "Professional login"
2. Field: **Professional code** * — with a **"Find Professional" / "Change Professional"** toggle button in the label
3. **Selected-professional card** replacing the input once chosen (shows `professional_name` + `professional_id`)
4. Field: **Username** * (`autocomplete=username`)
5. Field: **Password** * (`app-password-input`)
6. Button "Continue"; `loginMessage`
7. **"Need access?" aside** — explains client accounts are created/approved by a professional
8. **Legal note** with links to Client Terms and Client Privacy Notice + "you will be asked to accept the current version"
9. **Professional directory modal** (`showDirectory`): dialog header + eyebrow "Professional selection" + H2 "Find Professional" + subtitle; close button; **search input** with search icon and clear button; server-side search on Enter / change; loading state "Loading professionals..."; result rows showing **avatar initial, `professional_name`, `professional_id`, selection indicator (✓/›)**; empty states — "Type at least 3 characters to find your professional." and "No professionals match your search."; footer "Cancel" + "Continue" (disabled until a professional is pending)

**Flutter fields/actions:**
1. AppBar "Client Login"; `AuthBrand` "Client sign in"
2. Field: **Professional code** with a suffix search/expand `IconButton` toggling an inline panel
3. Field: **Username**
4. Field: **Password** (`PasswordField`)
5. Button "Sign in"; `FormMessage`
6. Inline directory panel: search `TextField` (**client-side filter only**, over the whole loaded list); loading spinner; "No professionals found."; `ListTile` rows showing **`professionalName`** as title and **`professionalId · professionalHeadline`** as subtitle
7. Routes to change-password when `mustChangePassword`

**Gap:**
- Missing: **"Need access?" help aside** — clients have no on-screen explanation of where credentials come from.
- Missing: **legal note + Client Terms / Client Privacy links**.
- Missing: **selected-professional confirmation card** (Flutter just fills the code field).
- Missing: **"type at least 3 characters" guidance**; Flutter loads the entire directory and filters locally, Angular searches server-side — a scale difference worth flagging.
- Missing: two-step pick → "Continue" confirmation (Flutter selects immediately).
- Missing: "Professional workspace? → Professional login" cross-link.
- Flutter *adds* `professionalHeadline` to the row subtitle (Angular shows only name + code).

---

## 9. Client Change Password (`/client/change-password`) — forced first-login gate

- **Angular:** `client/client-change-password/client-change-password.component.html`
- **Flutter:** `lib/features/client/client_change_password_page.dart`
- **Status:** **Built but fields differ**

**Angular fields:** topbar brand + "Back to Login"; eyebrow "Client Portal"; H1 "Set a new password"; **New password** (`app-password-input`) with helper "At least 8 characters with 1 special character."; **Confirm new password**; "Save New Password" / "Saving..."; `message`; **not-logged-in branch** showing "Please login to continue." + Client Login button.

**Flutter fields:** AppBar "Set your password" + **"Sign out"** action; `AuthBrand`; **Temporary password** field; **New password**; **Confirm new password**; helper "At least 8 characters."; "Save and continue"; `FormMessage`; token rotation handled on success.

**Gap:**
- Flutter **adds a required "Temporary password" (current password) field** that Angular does not collect — the two flows call the API differently. Confirm which contract is correct; this is a functional divergence, not just cosmetic.
- Flutter helper says "At least 8 characters" but Angular requires **8 chars + 1 special character** — Flutter's stated rule is weaker than the backend rule.
- Missing: not-logged-in fallback branch.

---

## 10. Client Legal Consent (`/client/legal-consent`)

- **Angular:** `client/client-legal-consent/client-legal-consent.component.html`
- **Flutter:** **none**
- **Status:** **Missing entirely**

**Angular elements:** brand topbar + "Client access" badge; eyebrow "First-time client review"; H1 "Review how RepRoot Studio works"; intro; **"Effective {date} · Version {n}"**; **relationship note** ("Your professional manages your coaching relationship." / "RepRoot Studio provides the software. Your professional decides what information and activities to request."); two document links — *Client Terms & Conditions* ("Responsibilities, professional relationship, payments, and safety.") and *Client Privacy Notice* ("What RepRoot processes, what your professional controls, and your choices."); consent checkbox; error slot; "Accept and Continue" / "Saving..." button.

**Flutter:** none.

**Gap:** Entire first-time client consent gate missing, including the relationship-disclosure note that sets expectations about professional vs platform responsibility.

---

## 11. Public Lead Form (`/public/forms/:publicSlug`)

- **Angular:** `client/public-lead-form/public-lead-form.component.html` (176 lines) + `.ts` (201 lines)
- **Flutter:** **none**
- **Status:** **Missing entirely** (arguably out of scope — public web link)

**Angular elements:** form title (H1); **dynamically rendered custom fields** from the lead form definition (label + required marker, input type per `field_type`); submit button; success screen "Your form has been submitted successfully."; **introductory-meeting offer block** — H2 "Request {meeting title}", `meetingMessage`, **slot buttons** with selection state, **"Mobile number (optional backup contact)"** field, "Request meeting" button.

**Flutter:** none.

**Gap:** No mobile equivalent. Likely correct (it is a public, unauthenticated link consumed in a browser), but the meeting-request slot picker has no mobile analogue anywhere and should be confirmed as intentionally web-only.

---

## 12. Public Group Registration (`/public/group-registration/:publicSlug`)

- **Angular:** `client/public-group-registration/public-group-registration.component.html`
- **Flutter:** **none**
- **Status:** **Missing entirely** (same web-only caveat)

**Angular elements:** H1 "Client Registration Form"; dynamic fields from the group registration form (label + required marker); "Submit Registration" / "Submitting..."; success screen "Your professional will review your information."

**Gap:** No mobile equivalent; professionals can share the link but cannot preview or fill it in-app.

---

# PART 2 — Professional Area

---

## 13. Professional Shell / Navigation & Notifications

- **Angular:** `shared/professional-page-shell/professional-page-shell.component.html` (134 lines)
- **Flutter:** `professional_tabs_shell.dart` + `professional_manage_page.dart` + `professional_more_page.dart` + `shared/notifications_page.dart`
- **Status:** **Partially built**

**Angular navigation items (8):** Dashboard · Forms & Groups · Templates · Clients (**with unread-message badge**) · Schedule · Resource · Profile · Settings. Plus: brand link, **data-usage gauge** (percent ring + "Data usage / N% / used"), **Sign Out** button with "Signing out..." state.

**Angular page header:** eyebrow, H1, subtitle, `page-actions` slot, and the **notification bell** — unread badge; dropdown panel with header "Notifications"; per-row **category icon, category name, timestamp, title, body, "Open details →"**; read/unread styling; empty "No notifications yet."; footer actions **"Clear All"** and **"Mark as Read"** (each disabled appropriately).

**Flutter navigation:** 4 bottom tabs — Dashboard · Manage · Clients · More.
- **Manage** hub: quick grid + "Recent items" (lead form / template / group rows with `StatusPill`) + "Waiting for review" submissions; links to forms-groups, groups, templates, resource, schedule, payments.
- **More** hub menu (6): Professional Profile · Resource Library · Plan & Storage · Settings · Help & Support · Notifications.
- **Notifications page:** AppBar "Notifications", "Read all" action, an "All" filter chip, empty state "No notifications here."

**Gap:**
- Missing: **data-usage gauge** in navigation (exists only buried under Settings → Plan & Storage in Flutter).
- Missing: **unread-message badge on the Clients nav entry** (Flutter shows unread per client row but not on the tab).
- Missing: notification row **category icon + category label + body preview + "Open details →"** affordance; Flutter rows are thinner.
- Missing: **"Clear All"** notification action (Flutter has only "Read all").
- Structural: Angular has 8 flat nav destinations; Flutter has 4 tabs + 2 hub pages. Resource, Schedule, Templates, Forms & Groups, Payments are all one level deeper on mobile.

---

## 14. Professional Dashboard (`/professional/dashboard`)

- **Angular:** `professional/professional-dashboard/professional-dashboard.component.html` (484 lines) + `.ts` (547 lines)
- **Flutter:** `professional_dashboard_page.dart` (915 lines)
- **Status:** **Partially built** — three tables, all reduced

**Angular content (full enumeration):**

*Header band:*
- **"Action Required"** onboarding panel — eyebrow "Workspace setup", `onboarding.message`, and a link per `onboarding.actions` (`action.label` → `action.route`)
- **"Current Plan: {plan_name}"** line
- **Workspace totals KPI row (4):** Total Clients · Total Groups · Total Templates · Total Resources — each with a value and a usage caption (`resourceUsageCaption`)
- **Tab strip (3)** with per-tab badges: Activity (`activityActionCount`) · Payments (`paymentsBadgeCount`, tooltip "Needs review, overdue, or has unread updates") · Schedules (`scheduleActionCount`)

*Activity tab:*
- KPI row (4): Messages / Unread messages · Requests / Pending lead requests · Account / Client account requests · Total / Items waiting on you
- `activityChart` (chart-renderer)
- **Messages list** (visibleRows=5): avatar initials, client name, `lastAt` timestamp (`MMM d, h:mm a`), unread count badge (99+ cap); links to client chat tab; empty "No unread messages."
- **Pending Requests list** (visibleRows=5) with "View All" → forms-groups: avatar initials, `applicant_name`, `email` + `submitted_at` (mediumDate); empty "No pending requests right now."
- **Client Account Requests table (6 columns, visibleRows=6):** `Client` · `Group` · `Requested` (dd MMM yyyy, h:mm a) · `Request` (chip: "Delete account" or "N profile fields") · `Client Note` · `Action` (Approve + Keep Account for deletions, "Review Edit" link otherwise); empty "No client account requests are waiting for review."

*Payments tab:*
- **Revenue panel** with reporting currency, **period picker** (`revenuePeriodOptions`) and a **custom range** row (From / To date inputs + Apply)
- Revenue KPI row (3): Total Logged / Private payment records · Manual Logs / period range · Integrated Payments / "Available after provider setup"
- `revenueChart`
- **Recent Transactions table (5 columns, visibleRows=5):** `Client` · `Amount` (amount + currency) · `Received` (dd MMM yyyy) · `Status` (chip: Partial / Refunded / Completed) · `Actions` (View → client payments tab); empty "No payments recorded yet."
- **Locked state** when currency unset: "Choose your reporting currency" card with a 3-step ordered list and "Open Payment Settings" button
- Payments-action KPI row (2): Awaiting review / Proofs submitted by clients · Overdue / Past their due date
- `paymentsChart`
- **Recent Updates** notification list (title + `created_at`), tappable to the client payment
- **Needs Action table (6 columns, visibleRows=6):** `Client` · `Title` · `Amount` · `Due` (or "No due date") · `Status` (chip) · `Actions` (Review deep-link with `tab/paymentTab/request` query params); empty "No payments need action right now."

*Schedules tab:*
- KPI row (4): Past due / Overdue schedules · Immediate / Due within 24 hours · This week / Due within 7 days · Recent progress / Completed in last 7 days
- `scheduleChart`
- **Schedules table (7 columns, visibleRows=8):** `Client` · `Schedule Title` · `Date` (dd MMM yyyy) · `Time` (or "Not set") · `When` (relative chip with overdue/soon styling) · `Status` · `Actions` (Open Client + Mark Complete); **group header rows** separating overdue from upcoming with counts; empty "No pending schedules."

**Flutter content:**
- AppBar "Dashboard"; `_Hero` "Welcome back, {name}"
- **Overview KPI grid (5):** Clients · Forms · Groups · Resources · Lead Forms
- Tab bar (3) with badges: Activity / Payments / Schedules
- Activity: KPIs (3) Unread · Requests · Account; `activityChart`; **"Pending requests"** list (applicantName + "Submitted {date}" + `StatusPill('Review')`); **"Unread messages"** list (name + "N unread messages" + count pill); **"Account requests"** cards (clientName + `StatusPill('Deletion'|'Profile edit')` + note text + Approve / Decline buttons)
- Payments: KPIs (2) Awaiting review · Overdue; **Revenue card** with period `ButtonSegment`s, "Total" and "This month" figures; revenue chart; **"Needs action"** list (clientName title + item title subtitle)
- Schedules: KPIs (4) Overdue · Due 24h · Due 7 days · Done (7d); overdue/upcoming section headers with counts; rows = reminder title + client name

**Gap (field-by-field):**
- **Client Account Requests: 6 columns → 3 fields.** Missing on Flutter: **Group**, **Requested timestamp**, **proposed field count** ("N profile fields"). "Review Edit" deep-link for non-deletion requests is missing (Flutter offers Approve/Decline for everything).
- **Recent Transactions table (5 cols) is entirely absent** from Flutter's Payments tab — no per-transaction Client / Amount / Received / Status / View.
- **Needs Action: 6 columns → 2 fields.** Missing: **Amount**, **Due date**, **Status chip**, **Review action**.
- **Schedules: 7 columns → 2 fields.** Missing: **Date**, **Time**, **relative "When" chip**, **Status**, **Open Client** action, **Mark Complete** action.
- Missing: **"Action Required" onboarding panel** with actionable routes.
- Missing: **"Current Plan" line** and per-KPI **usage captions** (Angular shows "3 / 5" style limits; Flutter shows bare counts).
- Missing: **revenue custom date range** (From/To/Apply) — Flutter has preset periods only.
- Missing: **"Choose your reporting currency" locked-state card** with its 3-step instructions and deep link.
- Missing: **"Recent Updates" payment notification list**.
- Missing: **Manual Logs / Integrated Payments revenue split** (Flutter shows one total).
- Missing: **Messages list timestamps** (Angular shows `MMM d, h:mm a`; Flutter shows only the count).
- KPI mismatch: Angular's totals row is Clients/Groups/**Templates**/Resources; Flutter's is Clients/**Forms**/Groups/Resources/**Lead Forms** — Templates count is not surfaced.

---

## 15. Forms & Groups (`/professional/forms-groups`)

- **Angular:** `professional/professional-forms-groups/professional-forms-groups.component.html` (391 lines) + `.ts` (393 lines)
- **Flutter:** `professional_forms_groups_page.dart` (1160 lines)
- **Status:** **Partially built**

**Angular content (full enumeration):**

*Header:* "Refresh" action; "Add Client" action (when groups exist).

*Workspace tabs (2):* **Lead Forms** ("N of M used") · **Client Groups** ("N managed groups").

*Lead Forms tab:*
- **Form selector dropdown** listing every lead form as "{title} (Active|Disabled)"
- Usage counter "N / M forms used" + "Create Form" button
- Empty state: "You haven't created a form yet." + a 3-item setup checklist (Public lead form / Minimum one group / Client creation form for that group) + Create Form
- **Lead panel:** eyebrow "Public enquiry form"; form title; active/inactive explanation; **enable/disable switch**
- **Public Form Link** box: full URL + "Copy Link"
- **Stats grid (4):** Total Requests · Pending · Approved · Deleted
- **Form Fields card:** "3 required" + list (First Name, Last Name, Email Address) + "N more fields"
- "Edit Form" action
- **Introductory Meeting Settings block:** eyebrow "After form submission"; explanation; **enable switch**
  - **Meeting requests list:** `applicant_name`, `requested_start` (EEE, MMM d, y · h:mm a), `reference_id · contact_email`, status pill, and for pending — **"Accept & send invite"** / **"Decline"**
  - **Meeting rule grid (4):** Duration (minutes) · Minimum notice (hours) · Booking window (days) · Buffer (minutes)
  - **"Next introductory meetings"** preview (next 5): applicant name, "Lead-form introductory meeting · {reference_id}", time, "Open meeting" link; empty note
  - **"Overdue follow-up"** block: applicant name, timestamp · contact email, **per-meeting free-text textarea** with a default apology placeholder, **"Send email"** button
  - "Edit meeting settings" / "Set up introductory meetings" action
- **Form Requests panel:**
  - **Month filter** select ("Last 6 months" + `monthOptions`)
  - **Status tabs (3):** Pending (n) · Approved (n) · Deleted (n)
  - **Table (7 columns, visibleRows=6):** `#` · `Applicant Name` · `Email` · `Submitted On` (medium) · `Reference ID` · `Group` (with not-assigned styling) · `Actions` ("View Profile" if converted, else "View"; plus **Delete** for pending)
  - Empty: "No {view} forms found."

*Client Groups tab:*
- Heading "Groups (N / M)" + description + **"Create Group"**
- **Drag-to-reorder** group list (`cdkDropList`, ⠿ handle) with a drag hint about lock priority
- Group row: name, description (or "No description added yet."), "Active" pill, **"Group registration form ready / needed"**, **"Open group"**, **"Edit form"**
- **Locked Groups** section: same rows with a 🔒 lock badge, "Locked" pill, and disabled Open/Edit buttons
- Empty: "No groups yet / Create a group to finish setup."

**Flutter content:**
- AppBar "Forms & Groups"; segments **Form / Groups / Requests**
- Form tab: form title, `StatusPill('Live'|'Disabled')`, share button, "Create form" / "Edit form", **Form enabled** switch, **Introductory meeting** switch, **"Fields"** list (label + type/required subtitle), inline editor (Form title + Add field + `_FieldEditor` with Label / Type / Options / Required / Remove)
- **Meeting settings dialog:** Meeting title · Duration (minutes) · Minimum notice (hours) · Max advance (days) · "Requires my approval" switch
- Groups tab: "New group" toggle → Group name + Description + "Create group"; "Your groups" list (name, description, `StatusPill('Form')`)
- Requests tab: **Pending (n)** and **Approved (n)** sections; row = applicantName + email/date + `StatusPill('Client')`; expanded card → **Create client access** (Group dropdown, Username, Temporary password + Generate, Create client / Cancel), plus **Approve** and **Delete** actions; success dialog with Username + password + Copy

**Gap (field-by-field):**
- **Form Requests table: 7 columns → 2 fields.** Missing on Flutter: **`#` index**, **Email as a column**, **Submitted On**, **Reference ID**, **Group**, and the **"View Profile"** deep-link for converted submissions.
- Missing: **Deleted requests tab** entirely (Flutter has Pending + Approved only).
- Missing: **month filter**.
- Missing: **stats grid (Total / Pending / Approved / Deleted)**.
- Missing: **multi-lead-form support** — Angular has a form selector and an "N of M forms used" quota; Flutter assumes a single lead form.
- Missing: **public form link display + Copy Link** (Flutter has a share sheet but never shows the URL).
- Missing: **"3 required" universal-fields card**.
- Missing: **meeting requests accept/decline** on this page ("Accept & send invite" / "Decline").
- Missing: **"Next introductory meetings" preview**.
- Missing: **"Overdue follow-up" block with the per-meeting email textarea and Send email** — an entire client-recovery workflow with no mobile equivalent.
- Missing: **meeting Buffer (minutes)** setting (Flutter has title/duration/notice/max-advance only).
- Missing: **group drag-to-reorder** (lock priority) and the **Locked Groups** section with lock badges and disabled actions.
- Missing: group row's **"registration form ready/needed"** status text and the direct **"Edit form"** action.
- Missing: **empty-state setup checklist** (lead form → group → client creation form).

---

## 16. Lead Form Create / Edit (`/professional/forms/create`)

- **Angular:** `professional/professional-lead-form-create/professional-lead-form-create.component.html` (106 lines) + `shared/form-field-builder/*` (288 + 305 lines)
- **Flutter:** inline editor inside `professional_forms_groups_page.dart`
- **Status:** **Partially built**

**Angular fields (full list):**
*Step 1 of 2 — Form:*
1. **Form name** text input
2. **`app-form-field-builder`** — the shared dynamic-field builder (field label, type, options, required, placeholder, suggestion groups, reordering)
3. "Save and continue" button; message slot

*Step 2 of 2 — Meeting:*
4. H2 "Offer an introductory meeting?" + explanation
5. **Toggle:** "Allow applicants to request a meeting" (disabled when no availability)
6. **No-availability warning** + "Open scheduling setup" link
7. **Meeting title** text input
8. **Display duration** select — 15 / 30 / 45 / 60 minutes
9. **Minimum notice** select — 4 / 12 / 24 / 48 hours
10. **Book up to** select — 7 / 14 / 30 / 60 days ahead
11. **Buffer between meetings** select — No additional buffer / 10 / 15 / 30 minutes
12. Manual-approval note
13. "Back to form" + "Save and continue to groups" / "Skip and continue to groups"

**Flutter fields:** Form title; Add field + `_FieldEditor` (Label, Type, Options, Required toggle, Remove); Save form / Cancel. Meeting settings live in a separate dialog: Meeting title, Duration (minutes, free numeric), Minimum notice (hours, free numeric), Max advance (days, free numeric), "Requires my approval" switch.

**Gap:**
- Missing: **two-step wizard framing** ("Step 1 of 2" / "Step 2 of 2") and the guided hand-off to group creation.
- Missing: **Buffer between meetings** field.
- Missing: **availability precondition check** — Angular disables the meeting toggle and links to scheduling setup when no availability exists; Flutter lets you enable it regardless.
- Missing: **constrained select options** — Flutter uses free numeric text for duration/notice/advance where Angular offers fixed valid choices.
- Missing: **field placeholder** and **suggestion groups** support from `form-field-builder`.
- Missing: manual-approval explanatory note.

---

## 17. Group Create (`/professional/groups/create`)

- **Angular:** `professional/professional-group-create/professional-group-create.component.html`
- **Flutter:** inline "New group" form in `professional_forms_groups_page.dart`
- **Status:** **Built but fields differ**

**Angular elements:** eyebrow "Step 2"; intro card "Groups help you organize clients" + **example chips** (Bulk, Weight Loss, Mobility, Strength, General Fitness); **Group Name** input; **Group Description optional** textarea (rows=4); **"Next step is required" notice card** explaining that a client creation form with five recommended fitness fields is auto-created and you'll be taken to it; message slot; "Create group and continue" / "Creating...".

**Flutter elements:** "Group name" `TextField`; "Description" `TextField`; "Create group" / "Creating…" button.

**Gap:** Same two data fields, but missing all guidance: **step framing**, **example chips**, and — importantly — the **"next step is required" notice** plus the auto-navigation to the group's client-creation form. On mobile a professional can create a group and never realise a registration form was generated.

---

## 18. Client Registration Form Builder (`/professional/groups/:groupId/client-form/create`)

- **Angular:** `professional/professional-client-form-create/professional-client-form-create.component.html`
- **Flutter:** "Edit registration form" section in `professional_group_detail_page.dart`
- **Status:** **Built but fields differ**

**Angular elements:** eyebrow "Step 3"; **group context card** (Group label, name, description); **toggle** "Require this form to be completed before a client can be added to this group"; **`app-form-field-builder`** with **`externalSuggestionGroups`**; "Save client creation form" / "Saving..."; message slot.

**Flutter elements:** "Edit registration form" heading + explanation; Add field + `_FieldEditor` (Label / Type / Options / Required / Remove); **"Require before adding a client"** switch with subtitle "Clients must complete this form first"; Save form / Cancel.

**Gap:** Missing **`externalSuggestionGroups`** (Angular suggests fields sourced from elsewhere in the workspace); missing group-context card; missing step framing; missing field **placeholder** support.

---

## 19. Group Detail (`/professional/groups/:groupId`)

- **Angular:** `professional/professional-group-users/professional-group-users.component.html` (510 lines) + `.ts` (390 lines)
- **Flutter:** `professional_group_detail_page.dart` (992 lines)
- **Status:** **Partially built** — CSV import is the big miss

**Angular content (full enumeration):**

*Header actions:* "Back to Forms & Client Groups" · **"Add Client"** · **"Edit Group"**.

*Summary band:* "Active" pill, group name, description; **stats (4):** Total Clients · Active Clients · Pending Invites · Registration Form (Ready/Needed).

*Tabs (5):* Overview · Pending Users · Approved Users · Registration Form · Settings.

*Overview:* **Overview cards (4)** — Total users ("All clients ever added to this group.") · Approved count ("Clients with active portal access.") · Pending count ("Registration requests awaiting your review.") · Pending invites ("Clients still on a temporary password."). **Recent Activity** list: avatar initials, first+last name, email; empty "No approved users yet."

*Pending Users:* header + count badge; per submission (visibleRows=8): **`applicant_name`**, **`email`**, **`reference_id` · "Source: Group Registration Form" · "Submitted {medium}"**, **`missingRequiredFields()` warning** ("Missing: a, b, c"), actions **"Approve"** (deep-links to Add Client prefilled with `registrationSubmissionId`) and **"Decline"** / "Declining..."; empty "No pending registration requests."

*Approved Users:* "N users shown"; actions **"Import Clients"** and **"Refresh"**; filters — **search** ("Search by name, email, or username") and **status select** (All / Active / Pending password change).
**Table (7 columns):** `#` · `Client Name` (avatar + name) · `Email` · `Username` (or —) · `Status` (Active/Inactive pill + "No portal access" pill) · `Joined On` (mediumDate) · `Actions` ("View Profile"). Empty: "No users found for this group."

*Registration Form:* header + mandatory/optional pill; **"Share Registration Form"** and **"Edit Form"**; flow note ("Known client → group-specific details → professional review → account credentials"); **Form Link** box with URL + "Copy Link" (or a pending message); **field groups** — "Universal Fields" (first 3, each "Required") and "Custom Fields" (label + "{field_type} - Required|Optional"); empty "No custom registration fields yet."

*Settings:* collapsible "Group Settings" accordion (Open/Closed pill) → **Group Name** input, **Group Description** textarea (rows=5), "Save Group".

***CSV Import modal (3 steps):***
- **Upload:** explanation, **CSV file picker** (`.csv,text/csv`), "Reading file..."
- **Preview:** "N row(s) detected in {filename}"; **mapping table (3 columns): `File Column` · `Maps To` (select over form fields, with "(required)" markers, or "Ignore this column") · `Match` (Exact match / Partial match / Unmatched pill)**; "N column(s) will be ignored on import."; **raw preview table** of the first rows with every file column as a header; **toggle** "Create login access for these clients (off by default - imported clients are info-only)"; nested **toggle** "Email generated usernames and temporary passwords to each client"; "Choose a different file" + "Confirm Import" / "Importing..."
- **Result:** result message; **Created table (4 columns): `Row` · `Client` · `Email` · `Portal Access` (Yes/No)**; **Failed table (2 columns): `Row` · `Reason`**; "Done"

**Flutter content:**
- AppBar = group name; segments **Members (n) / Requests (n) / Settings**
- Members: **selection mode** ("Select" / "Done", "Select all" / "Clear") with **bulk Activate / Deactivate**; rows = displayName (or username) title, email (or username) subtitle, Active/Inactive `StatusPill`
- Requests: **Pending (n)** and **Converted (n)**; row = applicantName + email + `StatusPill('Client')`; expanded → "Create client access" (Username, Temporary password + Generate, Create client / Cancel), "Convert to client"; success dialog with Username + password + Copy
- Settings: **Group details** (Name, Description, Save group); **Registration form** card (`StatusPill('Active')`, field list with label + type, "Create form" / "Edit form"); **Registration link** with **Share link**; inline registration-form editor (Add field, `_FieldEditor`, "Require before adding a client" switch, Save/Cancel)

**Gap (field-by-field):**
- **Approved Users table: 7 columns → 3 fields.** Missing: **`#` index**, **Username as its own column** (Flutter only falls back to it), **Joined On**, **"No portal access" pill**, **"View Profile" action**.
- Missing: **search box** and **status filter** on the member list.
- **Missing: the entire CSV Import workflow** — file picker, column-mapping table (File Column / Maps To / Match confidence), ignored-column count, raw preview table, portal-access toggle, email-credentials toggle, and both result tables (Created: Row/Client/Email/Portal Access; Failed: Row/Reason). This is the single largest missing feature in the professional area.
- Missing: **Overview tab** and its 4 explanatory cards; missing **Recent Activity** list.
- Missing: **summary band stats (4)** — Total Clients, Active Clients, Pending Invites, Registration Form status.
- Missing: **`missingRequiredFields()` warning** on pending registrations ("Missing: …").
- Missing: pending-submission metadata — **reference_id**, **"Source: Group Registration Form"**, **submitted timestamp**.
- Missing: **Decline** action on pending registrations (Flutter offers only convert).
- Missing: registration-form **mandatory/optional status pill**, **flow note**, **visible Form Link URL + Copy** (share-only on Flutter), and the **Universal vs Custom field grouping**.
- Flutter *adds* bulk activate/deactivate with multi-select — Angular has no equivalent. Worth keeping and possibly back-porting.

---

## 20. Form Request Detail (`/professional/forms-groups/requests/:submissionId`)

- **Angular:** `professional/professional-form-request-detail/professional-form-request-detail.component.html` (152 lines) + `.ts` (344 lines)
- **Flutter:** partially covered by the expanded request card in `professional_forms_groups_page.dart`; **no dedicated page**
- **Status:** **Partially built**

**Angular fields (full list):**
1. Applicant card: eyebrow "Applicant", **applicant_name**, **reference_id pill**
2. Meta grid (2): **Email** · **Submitted on** (medium)
3. **"Submitted answers"** definition list — every submitted field label + value
4. "Create client access" panel with explanation
5. **Client photo** — preview or initial placeholder, "Upload photo" / "Change photo" file input, "Remove"
6. **Group** select * (groups without a registration form are disabled)
7. **Portal access mode radio (3):** "Create with portal access — email login details to the applicant" · "Create with portal access — don't email, I'll share the credentials manually" · "No portal access — just store this applicant's info"
8. **Client username** *
9. **Client password** * (`app-password-input`)
10. **Confirm password** *
11. Non-portal hint: "No username or password will be created. You can grant portal access later from the client's profile."
12. **"Client registration answers"** — every field of the selected group's registration form, auto-filled from the submission, rendered by type (textarea / select / input), with core fields read-only
13. "Create client access" / "Creating..." button

**Flutter fields:** applicantName, submitted date, then "Create client access" → **Group** dropdown, **Username**, **Temporary password** + Generate, Create client / Cancel; plus Approve and Delete.

**Gap:**
- Missing: **dedicated detail route** — no way to open a submission on its own screen.
- Missing: **"Submitted answers"** display. On mobile a professional approves an applicant **without being able to read what the applicant submitted.** Functionally serious.
- Missing: **reference_id**, **email** in the detail view.
- Missing: **client photo upload**.
- Missing: **3-way portal access mode radio** — Flutter always creates portal access; there is no "no portal access, info only" option and no "don't email" option.
- Missing: **Confirm password** field.
- Missing: **auto-filled registration answers form** with per-type rendering and read-only core fields.
- Missing: disabling groups that have no registration form.

---

## 21. Manual Client Create (`/professional/clients/add`, `/professional/groups/:groupId/clients/add`)

- **Angular:** `professional/professional-manual-client-create/professional-manual-client-create.component.html` (118 lines) + `.ts` (235 lines)
- **Flutter:** `professional_client_create_page.dart` (435 lines)
- **Status:** **Built but fields differ** — significant

**Angular fields (full list):**
1. Header: "Cancel" action (context-aware back target)
2. Message banner with success note "Taking you to their profile..."
3. Empty state when no groups: "A client registration form is required." + "Open Forms & Groups"
4. Section heading "Client information" + **source pill** ("Group registration" or "Manual entry")
5. **Group** select * (locked when entered from a group, with explanatory note)
6. **Dynamic registration fields** — every field of the selected group's client-creation form, rendered by `field_type` (long_text/address → textarea; options → select with placeholder; else typed input), honouring `required`
7. Section "Account access" + explanation
8. **Portal access mode radio (3):** send credentials by email · create but share manually · no portal access
9. **Username** *
10. **Temporary password** * (`app-password-input`) + **"Generate"** button
11. **Reference ID** (read-only, "Generated automatically on creation")
12. Non-portal hint
13. "Open Client" link once created; "Create Client Account" / "Creating..."

**Flutter fields:**
1. AppBar "Add Client"
2. **Group** dropdown
3. **First name**
4. **Last name**
5. **Email**
6. **Phone (optional)**
7. **Username**
8. **Temporary password** + "Generate"
9. (implicit email-credentials behaviour)
10. Success card: "Client created", **Username**, **Temporary password** (mono, selectable), **"Credentials emailed"** row, "Done"

**Gap:**
- **Structural mismatch: Flutter hard-codes First name / Last name / Email / Phone; Angular renders the group's configured registration form dynamically.** Any custom field a professional configured (goals, injuries, height, plan, etc.) simply cannot be captured on mobile at create time.
- Missing: **3-way portal access mode radio** — no "don't email" and no "info-only client" option.
- Missing: **Reference ID** field.
- Missing: **source pill** (group registration vs manual entry) and prefill from a `registrationSubmissionId`.
- Missing: **group-locked mode** with explanation when entered from a group.
- Missing: **no-groups empty state** pointing to Forms & Groups.
- Missing: **"Open Client"** navigation after creation (Flutter's success card just has "Done").

---

## 22. Clients List (`/professional/clients`)

- **Angular:** `professional/professional-clients/professional-clients.component.html` (112 lines) + `.ts` (173 lines)
- **Flutter:** `professional_clients_page.dart` (385 lines)
- **Status:** **Built but fields differ** — the flagship 8-column table

**Angular content:**
- Header action: **"Refresh"**
- **Summary band (4):** Total Clients · Active Clients · Pending Passwords · Groups
- Panel header: "Client List" + "N clients shown"
- **Filters (3):** search input ("Search by name, email, username, or group") · **group select** ("All groups" + every group) · **status select** ("All statuses" / "Active" / "Pending password change")
- **Table — 8 columns:**
  1. `#` (row index)
  2. `Client Name` — avatar initials + first + last name + **unread-message badge**, links to the client profile
  3. `Email`
  4. `Group`
  5. `Username` (or —)
  6. `Status` — Active/Inactive pill **+ "No portal access" pill**
  7. `Joined On` (mediumDate)
  8. `Actions` — "Open"
- Empty: "No clients found. Approve a form request and create client access first."

**Flutter content:**
- AppBar "Clients"; search field ("Search clients...")
- **Filter segments (3):** All Clients / Active / Inactive
- **`_GroupChips`** group filter row
- **Row (3 slots):** title = `displayName`, subtitle = `groupName` (or "No group"), trailing = unread badge **or** Active/Inactive `StatusPill`
- 5s polling refresh; unread chats float to the top

**Gap (column-by-column):**
| Angular column | In Flutter? |
| --- | --- |
| `#` index | **No** |
| Client Name | Yes (title) |
| **Email** | **No** |
| Group | Yes (subtitle) |
| **Username** | **No** |
| Status | Partial — pill shown **only when there is no unread badge**; the two share the trailing slot |
| **"No portal access" pill** | **No** |
| **Joined On** | **No** |
| Actions ("Open") | Implicit (row tap) |

- Also missing: **summary band (Total / Active / Pending Passwords / Groups)**, the **"N clients shown"** count, and an explicit **Refresh** control.
- Filter mismatch: Angular's status filter is All / Active / **Pending password change**; Flutter's is All / Active / **Inactive** — "pending password change" is not filterable on mobile.
- **Owner decision needed:** with 8 columns and room for ~5, the natural mobile set is Name · Group · Status · Email · Joined On, with Username and Reference ID moved to the client detail screen and `#` dropped.

---

## 23. Client Profile — Professional View (`/professional/clients/:clientId`)

- **Angular:** `professional/professional-client-profile/professional-client-profile.component.html` (681 lines) + `.ts` (1367 lines)
- **Flutter:** `professional_client_detail_page.dart` (2095 lines)
- **Status:** **Partially built** — the single densest page in the product

**Angular content (full enumeration):**

*Identity card:* **photo upload** (file input over the avatar, "Photo" edit affordance); name; **Active/Inactive pill**; **"No portal access" pill**; **group link**; **"Joined on {dd MMM yyyy}"**; "Edit Profile" button.
**Client info grid** — `visibleClientInfoRows()` (label + value, "Not added" fallback, readonly styling) with a **"Show all details (N more)" / "Show less"** expander.
**Edit form fields:** First Name · Last Name · Email Address · **Username** (only with portal access) · **Client Status** select (Active/Inactive) · **Reference ID** (disabled) · **every editable registration field**, rendered by type. Actions: Cancel · "Save Client Information" / "Saving...".

*Pending change-request card:* eyebrow "Client Profile Update"; "Profile edit awaiting review (Pending)"; **"Requested {dd MMM yyyy, h:mm a}"**; **client note**; **change table — 3 columns: `Field` · `Current` · `Requested`**; empty "This request does not change any details."; **optional note textarea to the client**; "Reject" · "Approve changes" / "Saving...".

*Workspace tabs (4):* Client Workspace · Chat (**with unread badge**) · Payments (when enabled) · Actions.

*Workspace tab:*
- **Client Activity grid (4):** Total Entries / This month · Last Entry (date + template name, or "No entries yet") · Streak (N Days + "Keep it up!"/"No current streak") · Completion (% / This month)
- **Recent Entries** list: template name + entry date + chevron, tappable
- **Professional Notes (Private):** "Edit Note", textarea with placeholder, Cancel/Save, "Last updated: {dd MMM yyyy, h:mm a}", empty "No notes yet. Only you can see what you write here."
- **Follow-up Scheduler:** "Schedule Meeting" deep link
  - **Pending meeting requests:** "Meeting request: {title}", start time, notes, **Accept** / **Decline**
  - **Upcoming meetings:** title, start time, notes, **Join Link**, **Reschedule**, **Cancel**
  - **Reminder form:** **Reminder title** · **Date** · **Time** · **Notes (optional)** · **"Notify me" checkbox** · "Schedule reminder" (or Cancel/"Save changes" in edit mode)
  - **Reminder list:** title, date + time, notes, **status**, **Edit** · **Complete** · **Delete**
- **Assigned Templates:** per assignment — accent icon, template name, "Assigned on {date}", **client access level toggle group** (`accessLevelOptions`), **Unassign**, chevron; hint explaining private vs view-only; **assign row:** template select ("{name} ({cadence})") + **access level select** + "Assign"; empty note
- **Additional Information:** **Private / Shared with Client** toggle; items with **type badge**, title, text or reference title, **Open** (links) and **Remove**; **add form:** Title · **Type select (Text / Link / Reference)** · conditional Text textarea / URL input / **reference picker from the resource library**; "Add item"

*Chat tab:* `app-chat-panel` — header "Client Chat" + description + **message count**; **safety caution banner** ("avoid sending passwords, payment details…"); message bubbles with **sender label**, **image attachment (tappable to full size)**, text, timestamp; empty "No messages yet. Send the first note."; compose textarea with role-specific placeholder; **image attach button** (jpeg/png/webp/gif) with **pending-image preview + remove**; "Send Message".

*Payments tab:* `app-client-payments-tab` — see §25.

*Actions tab:* status pill (Active/Suspended) + "No portal access" pill.
- **"Everyday account controls"** (with "Reversible — none of these touch the client's data."): **Reset Password** · **Disable Portal Access** / **Grant Portal Access** · **Suspend / Reactivate Account**
- **Reset password block:** New temporary password * · Confirm password * · **"Reset & Send"** · **"Generate"** · Cancel; result "Temporary password: X"
- **"Destructive data actions"** section
- **Clear Client History block:** explanation; **"Download Client Data"** export button; **verification grid — Current professional password · "Type {username} to confirm" · Reset reason (textarea)**; "Clear Client History" / "Clearing..."
- **Delete Account block:** explanation; **Download Client Data**; **verification grid — Current professional password · "Type {username} to confirm" · Deletion reason (textarea)**; "Delete Account" / "Deleting..."

*Account & Access dialog:* definition list (9): **Portal Access · Username · Email · Group · Reference ID · Submitted On · Joined On · Status · Password (Temporary password active / Client-managed password)**; **Grant Portal Access form:** Username * · Temporary password * · Confirm password * · **"Email these credentials to the client" checkbox** · Cancel/Grant.

**Flutter content:**
- `_Header` (name, Inactive pill), `_TabBar`
- Change request: Approve / Reject buttons
- **"Client information"** section + **Edit dialog: First name · Last name · Email · Username**
- **"Registration details"** section
- **"Additional information"** section + **"Share this section with the client"** switch + Add dialog: **Title · Type (Text/Link) · Text · URL · "Shared with client" switch**
- **"Professional notes"** with hint "Anything worth remembering about this client…"
- **Schedule:** "Title" (hint "e.g. Progress review") + "Add schedule"
- **Video meeting dialog:** Meeting length (15/30) · Title (optional) · Notes (optional) · Schedule
- **"Progress"** section; **"Assign a template"** (Template dropdown) ; **"Assigned templates"**
- **Chat:** message list + "Message…" composer
- **Reset password dialog:** Temporary password · Reset
- **Destructive actions:** "Your current password" · "Type {expected} to confirm" · "Reason" · Cancel
- `_ActionRow`s for the account controls

**Gap (field-by-field):**
- **Client info edit: missing `Client Status` select, missing `Reference ID` display, and missing all editable registration fields.** Flutter edits only 4 fixed fields.
- Missing: **"Show all details (N more)" expander** and the full client-info grid.
- Missing: **photo upload** on the identity card.
- Missing: **group link** and **"Joined on"** date.
- **Change request: missing the 3-column `Field / Current / Requested` diff table** — Flutter shows Approve/Reject with no visibility into what actually changed. Approving blind is a real risk.
- Missing: **client note on the change request**, **requested timestamp**, and the **professional's optional note back to the client**.
- Missing: **Client Activity KPI grid (4)** — Total Entries, Last Entry, Streak, Completion %.
- Missing: **Recent Entries** quick list.
- Missing: **notes "Last updated" timestamp**.
- Missing: **reminder Date / Time / Notes / "Notify me"** — Flutter's schedule form is title-only.
- Missing: **reminder list actions Edit / Complete / Delete** and per-reminder status.
- Missing: **pending meeting-request Accept / Decline** on this page.
- Missing: **meeting Join Link / Reschedule / Cancel** row actions.
- Missing: **template client-access-level toggle** and the **access-level select on assignment**, plus **Unassign** from this page and the private/view-only explanatory hint.
- Missing: **Additional Information "Reference" type** (picking from the resource library) — Flutter supports Text and Link only.
- Missing: **per-item Private/Shared toggle semantics** at section level vs Angular's section-level toggle *and* per-item behaviour.
- **Chat: missing image attachment entirely** (attach button, pending preview, remove, inline image bubbles), missing the **safety caution banner**, missing **message count**, missing **sender labels**.
- **Actions: missing "Download Client Data" export** (present twice on web), missing **Confirm password** on reset, missing **"Generate" password**, missing **Grant Portal Access form** (username/password/confirm/email-credentials checkbox), missing **Disable Portal Access**, missing **Suspend/Reactivate**.
- Missing: **Account & Access dialog** and all 9 of its rows (Portal Access, Username, Email, Group, Reference ID, Submitted On, Joined On, Status, Password state).

---

## 24. Client Template Detail (`/professional/clients/:clientId/templates/:assignmentId`)

- **Angular:** `professional/professional-client-template/professional-client-template.component.html` (424 lines) + `.ts` (599 lines)
- **Flutter:** `professional_client_template_page.dart` (469 lines)
- **Status:** **Partially built**

**Angular content:**
- Header actions: **"Share Resources"** · **"Start New Entry"** · "Back"
- **Detail tabs (4):** Overview · Resources · Data Entries · Progress
- *Overview:* status pill (Completed/…), "Assigned {date}", **client access level toggle**, **range tabs** (`rangeOptions`); **Numeric Summary** cards per field — label, **Average**, **Latest**, **Entries** count, **"Min X · Max Y"**, empty "No tracking data has been submitted for this field yet."; **Charts** grid
- *Resources:* "Assigned Resources" + "Share Resources"; `app-references-accordion`; **Template Notes** (`template.purpose`)
- *Data Entries:* **date filter From / To** + Clear; actions **New Entry** · **Export CSV** · **Export Excel**;
  **Table — 6 columns:** `Date` · `Time` · `Values` · `Note` · `Status` (By professional / Client pill) · `Actions` (View · Edit, **disabled with "Locked after 72 hours"**). Empty "No entries in this range."
- *Progress:* "Progress Records" + "+ Add Record"; **form:** Title · Date · **Status (optional)** · **Progress notes** · **Next step (optional)**; **timeline:** title, date, status pill, **Edit**, notes, **"Next: …"**, **"By {created_by}"**; empty note
- *Share Resources dialog:* search input; **category-grouped checkbox picker** (title + subcategory/type); "N selected"; Cancel · "Share Selected"
- *New Entry dialog:* **Entry date** + **every template field by type** (long_text textarea, yes_no select, dropdown select, rating select from `ratingSteps`, number/text input) + **Note**; Cancel · "Save Entry"
- *Edit Entry dialog:* **Recorded date** · **Recorded time** · every answer (with **image preview** for image values) · **Note**; Cancel · Save
- *View Entry dialog:* key/value list, note, Close · Edit (disabled when locked)

**Flutter content:** Range segments (7d / 30d / 90d / All); "Overview"; "Charts"; "Recent entries (N)" with `StatusPill('Edited')`; **"Log an entry"** inline form (fields by type: yes/no segments, rating chips, text/number, "Note (optional)"); "Unassign template?" dialog.

**Gap:**
- **Data Entries table: 6 columns → ~2 fields.** Missing: **Time**, **Note column**, **Status (By professional / Client)**, **View action**, **Edit action**, and the **72-hour edit lock**.
- Missing: **date From/To filter** and Clear.
- Missing: **Export CSV** and **Export Excel**.
- Missing: **Numeric Summary cards** — Average / Latest / Entries / Min / Max per field.
- Missing: **Resources tab** — assigned-resources accordion and Template Notes.
- Missing: **Share Resources dialog** entirely (search, category-grouped checkbox picker, selected count, save).
- Missing: **Progress tab** — records timeline and the Title/Date/Status/Notes/Next-step form.
- Missing: **client access level toggle** on this page.
- Missing: **View Entry** and **Edit Entry** dialogs, including **image-value preview**.
- Missing: **"Assigned {date}"** and template status pill.

---

## 25. Client Payments Tab (professional view, inside client profile)

- **Angular:** `shared/client-payments-tab/client-payments-tab.component.html` (518 lines) + `.ts` (734 lines)
- **Flutter:** `professional_client_payments_page.dart` (663 lines)
- **Status:** **Partially built**

**Angular content (full enumeration):**
- **Sub-tabs:** Summary · Requests · Transactions · Methods · Activity
- **Locked state** when reporting currency unset: "1. Open Settings → Payments." / "2. Choose and confirm your reporting currency."
- **Money received panel:** "Log Received Payment"; tiles (3) — **Total Logged** · **Manual Logs** · **Integrated Payments** ("Coming later")
- **Payment requests summary tiles (4):** Active · **Awaiting Acknowledgement** · **Overdue** · Completed Payments
- **Overpaid banner:** "{amount} {currency} extra on {request_id}"
- **Request list mode tabs:** Active (n) / Completed Payments (n)
- **Request form:** **Payment title** * · **Amount** * · **Currency** * (select) · **Due date** · **Description** · **"Allowed payment methods"** checkbox list of shared methods · Cancel/Save
- **Request row:** title, **`request_id` · amount + currency · "due {MMM d, y}"**, **"Paid X · Remaining Y"**, **"Overpaid by Z"**, **status pill**, actions **Review** / **Edit** / **Cancel**
- **Transaction tabs:** Manual Payment Log / Integrated Payments
- **Manual Payment Log table — 4 columns:** `Payment` (amount + currency, method label) · `Reference` (`payment_record_id`, request reference) · `Received` (MMM d, y) · `Status` (reporting amount + Partial/Refunded/Completed pill). Empty: "No payments have been recorded for this client yet."
- **Record Received Payment modal:** **Amount received** * · **Currency** * · **Date received** * · **Reporting amount ({currency})** * · **Reporting currency** select · **Transaction reference** · **Internal note (private)** ("Never shown to the client")
- **Available Payment Methods** sharing panel + Save
- **Payment Activity** feed ("Every payment action for this client, newest first")
- **Verification modal:** request title; **"Requested"** block (Amount, Due) · **"Client reported"** block (**Amount, Date, Txn, Method, Note, "File attached"**); **totals strip: Requested / Accepted so far / Remaining**; mode buttons **Acknowledge Payment · Request More Info · Reject Proof**; acknowledge options **Partially paid / Fully paid / Overpaid** with explanations + "Accepted after this proof" + **Note (optional)**; reject → **Reason for rejection** *; info → **"What do you need?"** *

**Flutter content:** AppBar "{client} · Payments"; "Methods this client can see"; "Requests" section; **New payment request** (Title · Amount · Currency · Description (optional) · "Methods the client can use"); "Cancel request?"; **Proofs** list (Ref, Status, professional note) with **Acknowledge / Request info / Reject**; "Log this payment?" dialog with **Internal note (optional)**; `_promptText` dialogs for reject reason and info request.

**Gap:**
- Missing: **Due date** on the payment request form.
- Missing: the **5 sub-tabs** structure — Summary, Transactions, Methods and Activity have no mobile equivalent.
- Missing: **Money received tiles (Total Logged / Manual Logs / Integrated Payments)**.
- Missing: **request summary tiles (Active / Awaiting Acknowledgement / Overdue / Completed)**.
- **Missing: Manual Payment Log table (4 columns)** — Payment, Reference, Received, Status.
- Missing: **Record Received Payment modal fields** — Amount received, Currency, **Date received**, **Reporting amount**, **Reporting currency**, **Transaction reference**. Flutter's log dialog captures only an internal note.
- Missing: **Payment Activity feed**.
- Missing: **verification modal detail** — Requested vs Client-reported side-by-side (amount/date/txn/method/note/file), the Requested/Accepted/Remaining strip, and the **Partially paid / Fully paid / Overpaid** acknowledgement options with the "Accepted after this proof" computation.
- Missing: **overpaid banner** and per-request **"Paid / Remaining / Overpaid by"** progress lines.
- Missing: **Edit request** action.
- Missing: **Active / Completed request list modes**.
- Missing: **currency-unset locked state** with setup steps.

---

## 26. Tracking Templates (`/professional/templates`)

- **Angular:** `professional/professional-templates/professional-templates.component.html` (128 lines) + `.ts` (201 lines)
- **Flutter:** `professional_templates_page.dart` (664 lines)
- **Status:** **Partially built**

**Angular content:**
- Header action: **"+ Create Template"**, or **"All 5 template slots are used"** note
- **Template Slots panel:** explanation + **"N / M slots used"** indicator
- **Standard Templates section:** per standard template card — **name**, **cadence label**, **"N fields"**, **purpose**, **full field-label preview list**, and either **"Added to your templates"** pill or **"Adopt Template" / "No free slots"** button
- **My Templates section:** hint "Fields are always optional for clients"; **drag-to-reorder** with a lock-priority hint;
  row fields (6): **⠿ handle** · **name** · **cadence pill** · **"N fields"** · **"N clients assigned"** · **purpose** · actions **Edit** / **Delete**
- Empty row: "No templates yet" + guidance
- **Locked templates list:** same fields + **🔒 Locked badge**, Edit disabled, Delete allowed

**Flutter content:**
- AppBar "Templates"; KPIs **"Templates used"** and **"Assigned clients"**
- **"Tracking Library"** list: template name + subtitle
- **"Standard templates"** list: name + subtitle + **"Adopt"**
- **Editor:** **Name** (hint "e.g. Daily Nutrition Log") · **Purpose** (hint "What does this track?") · **Cadence** dropdown · field list · **Add field** · Save / Cancel
- **`_FieldEditor`:** **Label** (hint "e.g. Weight (kg)") · **Type** · **Options** · **Scale** · Remove
- "{name} is in use" dialog with "Open Clients"; "Delete {name}?" confirm

**Gap:**
- Missing: **"N / M slots used"** panel and the slots-full state.
- Missing: standard-template card detail — **cadence**, **field count**, **purpose**, **field-label preview**, and the **"Added to your templates"** adopted state.
- Missing on template rows: **cadence pill**, **"N fields"**, **"N clients assigned"**, **purpose**.
- Missing: **drag-to-reorder** (lock priority) and the **Locked templates** section with 🔒 badges and disabled editing.
- Missing: the "fields are always optional for clients" guidance.

---

## 27. Tracking Template Create / Edit (`/professional/templates/create`, `/:templateId/edit`)

- **Angular:** `professional/professional-tracking-template-create/professional-tracking-template-create.component.html` (129 lines) + `.ts` (212 lines)
- **Flutter:** `_Editor` inside `professional_templates_page.dart`
- **Status:** **Built but fields differ**

**Angular fields:** template Name; Purpose; Cadence; accent; the field builder (label, type, options, scale/rating steps, unit, required) — plus create-vs-edit routing.

**Flutter fields:** Name · Purpose · Cadence · fields (Label / Type / Options / Scale) · Save / Cancel.

**Gap:** Missing **accent colour** selection (Angular uses `accent` for green/blue/orange/purple styling across templates, assignments and client rows — Flutter never sets it). Missing per-field **unit** (Angular's numeric stats render "{value} {unit}"). Confirm whether `required` is exposed.

---

## 28. Schedule (`/professional/schedule`)

- **Angular:** `professional/professional-schedule/professional-schedule.component.html` (551 lines) + `.ts` (963 lines)
- **Flutter:** `professional_schedule_page.dart` (739 lines)
- **Status:** **Partially built** — the calendar is the headline miss

**Angular content (full enumeration):**
- Header actions: **"Manage availability" / "Hide availability"** · **"Schedule Meeting"**
- **Timezone `<datalist>`** with offset labels
- **No-availability prompt:** "Set your weekly availability" + explanation + "Set availability"
- **Meeting defaults form (4):** **Timezone** (searchable datalist + offset hint) · **Default meeting length (minutes)** · **Slot interval (minutes)** · **Buffer between meetings (minutes)** · "Save meeting defaults"
- **Weekly availability:** add-block row — **Day** select · **Start** time · **End** time · "Add block"; **per-weekday rows** with **"Day off" badge**, block chips ("HH:MM–HH:MM" + remove ×), empty "No availability", **quick-add "+"** per day; "Save weekly availability"
- **Calendar section:** "Day off" button; **prev/next month** navigation + month label; **occupancy legend (4)** — Open / Light (up to 1 hr) / Moderate (1–3 hrs) / Busy (over 3 hrs); **month grid** with weekday header row and per-day cells showing day number, **"N meetings"**, and occupancy/day-off/today/selected styling; selection note ("Showing meetings on {date}" or "You're on a day off…") + "Show all upcoming"
- **Client Meeting Requests section:** "Needs approval" pill, client name, title, start–end time, notes, **"Accept & Confirm"** / **"Decline"**; empty note
- **Upcoming internal client meetings:** client name, **group-meeting guest list**, title, start–end, **clash warning "⚠️ Overlaps another meeting"**, actions **Join Link** · **Reschedule** · **Cancel**
- **Lead-form introductory meetings:** "Lead form" pill, applicant name, "{form_title} · {reference_id}", time range, "Open lead meetings", "Join meeting"
- **Past lead-form meetings** section with "Follow up"
- **Past & Cancelled** section with status pills
- **Schedule Meeting modal:** **Clients** * — **group quick-select chips** ("✓/+ {group} (n)"), **client search**, **checkbox client picker** (multi-select for group meetings), "N client(s) selected"; **Duration (minutes)**; **Title**; **Notes**; **Week starting** date; **"Show times in"** timezone; **slot chips grouped by day**; **"Or pick an exact date & time"** datetime-local; Cancel / "Schedule Meeting"
- **Reschedule modal:** week starting, timezone, slot chips, manual datetime, Cancel / "Confirm New Time"
- **Days off modal:** **"Whole weekday, every week"** with 7 toggle chips + explanation; **"Specific dates"** — Date input + "Add date" + list with remove; "Done"

**Flutter content:** AppBar "Schedule"; segments **Reminders / Meetings / Availability**; KPIs (4) Pending · Due 24 hours · Due 7 days · Completed (7d); "Upcoming"; "Intro meeting requests"; "Meetings" with **Reschedule** / **Cancel** (+ reason); **Scheduling settings dialog** (Timezone free text · Default duration · Slot interval · Buffer); **"Weekly availability"** list ("{weekday} · {start}–{end}") + **Add availability window dialog** (Day dropdown, From/To time pickers); delete-schedule confirm.

**Gap:**
- **Missing: the entire month calendar** — grid, month navigation, per-day meeting counts, **occupancy legend and shading**, day selection and filtering.
- **Missing: the Days-off system entirely** — recurring weekday-off toggles and specific-date days off, plus the "Day off" badges on availability rows.
- **Missing: the Schedule Meeting modal** — Flutter can reschedule and cancel but there is **no way to book a new meeting from the Schedule page**; in particular the **group quick-select chips**, **client search**, **multi-select client picker** (group meetings), **Title**, **Notes**, **week-based slot chips**, and the **manual datetime-local fallback**.
- Missing: **client meeting request Accept & Confirm / Decline** with full detail.
- Missing: **clash detection** ("Overlaps another meeting").
- Missing: **group-meeting guest list** display.
- Missing: **lead-form introductory meetings** and **past lead-form meetings** sections.
- Missing: **Past & Cancelled** section.
- Missing: **timezone datalist with offset labels** (Flutter is free text — "Timezone (e.g. America/New_York)"), and the per-view **"Show times in"** timezone override.
- Missing: **Join Link** action on meetings.
- Missing: **quick-add "+" per weekday** and **remove-block ×** chips.

---

## 29. Resource Library (`/professional/resource`)

- **Angular:** `professional/professional-references/professional-references.component.html` (396 lines) + `.ts` (737 lines)
- **Flutter:** `professional_resources_page.dart` (1110 lines)
- **Status:** **Partially built** — closest to parity of the large pages

**Angular content:**
- Header: **"Resources Used: N / M (or Unlimited)"**
- **Organisation guide note** (Category → subcategory → resource title)
- **Limit-reached message**
- **Search** input + **"+ Create Category"**
- **Drag-to-reorder categories** (⠿) with lock-priority hint
- Category header: **name**, **description**, **"N subcategories"**, **"N resources"**, **Edit**, **Delete**
- **"+ Add Subcategory"**; per subcategory: heading, **Delete**, **"+ Add Resource"** (disabled at limit), **drag-to-reorder resources**
- Resource row: ⠿, caret, **title**, **type pill**; expanded detail — **preview box** (**YouTube embed iframe**, image, text preview, or file/link tile), description, **meta (Subcategory, Created)**, **tags**, actions **Open · Edit · Duplicate · Delete**
- **Locked resources / locked categories** lists with 🔒 badges, explanatory copy, Open + Delete only
- **Resource editor:** **Title** · **Type** select · **Category** select · **Subcategory** select; type-conditional — **Video URL**, **PDF upload + "Or a PDF URL"**, **Text** textarea, **Image upload**; **Optional Description**; **Tags** (comma text); Cancel / Save Resource
- **Category editor:** create / edit / add-subcategory modes; **Category name** · **Category description** · **Subcategory** textarea (one per line); Cancel / Save Category

**Flutter content:** AppBar "Resource Library"; search ("Search resources…"); category rows with **`StatusPill(resourceCount)`**, "Subcategory" action; "No resources here yet."; resource actions **Open · Edit · Duplicate · Delete**; **category editor** (Name · Description · Subcategories); **resource editor** (Title · Category · Subcategory · Type · URL/Text · Description · Tags); **"Library usage"** card; delete confirm.

**Gap:**
- Missing: **"Resources Used: N / M"** header counter (usage exists but is buried in a card).
- Missing: **"N subcategories"** metric on category headers.
- Missing: **drag-to-reorder** for both categories and resources (lock priority).
- Missing: **Locked categories / locked resources** sections with 🔒 badges and restricted actions.
- Missing: **inline preview** — YouTube embed, image preview, text preview, file tile. (`shared/video/youtube_player_page.dart` exists, so a player is available but not wired as an inline card preview.)
- Missing: resource **meta rows (Subcategory, Created date)** and **tag chips** in the expanded view.
- Missing: **PDF upload** and the "Or a PDF URL" alternative; missing **Image upload** (Flutter's editor appears URL-based).
- Missing: **limit-reached messaging** and disabling "+ Add Resource" at the cap.
- Missing: the **organisation guide note**.
- Missing: **per-subcategory Delete**.

---

## 30. Professional Profile (`/professional/profile`)

- **Angular:** `professional/professional-profile/professional-profile.component.html` (207 lines) + `shared/professional-profile-form/*` (278 + 322 lines)
- **Flutter:** `professional_profile_page.dart` (658 lines)
- **Status:** **Built but fields differ**

**Angular fields (full list from the shared form, 20+):**
1. **Profile photo** — preview, "Upload/Change photo", **"Remove photo"**
2. **First name** *
3. **Last name** *
4. **Phone**
5. **Gender** * (select)
6. **Birth month** * (select)
7. **Birth year** * (select)
8. **Country** * (select, ISO list)
9. **State / Region** * (select, country-dependent)
10. **Professional headline** (maxlength 180)
11. **About me** (textarea) — with **Private/Public toggle**
12. **Professional type**
13. **Years of experience** (number)
14. **Specializations**
15. **Languages known**
16. **Training style** (textarea) — with **Private/Public toggle**
17. **Certification name**
18. **Certification issued by**
19. **Certification year** (select)
20. **Certificate PDF/image** upload
21. **Images** — repeatable: **Category** select · **Title** · **Image upload** · Remove; "Add Image"; Private/Public toggle
22. **Links** — repeatable: **Title** · **URL** · Remove; "Add Link"; Private/Public toggle
23. "Save profile" / "Saving..."

**Angular view page:** preview toggle; per-section **Private/Public** toggles for `professional_headline`, `about`, `professional_summary`, `experience`, `specializations`, `languages`, `training_style`, `certification`, `images`, `links` (10 visibility keys).

**Flutter fields:** header with **"Code: {professionalId}"** pill; **"Details"** section; **"Professional"** section; **"About"** section (About me, Training style); **"Client visibility"** section using the same 10 visibility keys (Headline, About me, Professional details, Specializations, Experience, Languages, Training style, Certifications, Images, Links); edit form with **Change photo**, **Gender**, **Birth month**, **Birth year**.

**Gap:**
- Missing: **Phone** field.
- Missing: **Country / State** editing on this page (only present in setup, and there as free text).
- Missing: **Certification name / issued by / year** and the **certificate file upload**.
- Missing: **Images repeater** (category + title + upload + remove).
- Missing: **Links repeater** (title + URL + remove).
- Missing: **"Remove photo"** action.
- Missing: **Years of experience**, **Professional type**, **Specializations**, **Languages known** as editable inputs (they render read-only on Flutter).
- Missing: **profile preview toggle** ("see what clients see").
- Visibility keys match 1:1 — good.

---

## 31. Account Settings (`/professional/account-settings`)

- **Angular:** `professional/professional-account-settings/professional-account-settings.component.html` (597 lines) + `.ts` (643 lines)
- **Flutter:** `professional_settings_page.dart` (738 lines)
- **Status:** **Partially built**

**Angular sections (10) and their fields:**
1. **My Account** — account summary
2. **Professional Code** — "Current professional code" display; **"Change professional code"** input (placeholder "e.g. FITJOHN"); Save
3. **Change Password** — **New Password** · **Confirm New Password** (with mismatch error "Confirm password must match new password."); Save (gated on requirements + match)
4. **Delete Professional Account**
5. **Plan & Billing** — Refresh; **Current Usage** (Groups · Templates · Resources · Storage) + **"Data usage"** shortcut; **Choose Your Plan** with a **billing-cycle select** (monthly / 6 months / year) and **"Save N%"** badges; per-plan cards with price and CTA; **Membership** block — Active pill, **"Renews {date}"**, **"Cancellation scheduled — access ends {date}"**; **"Step down to:"** radio (pro / starter_free); billing portal button
6. **Payment Settings** — links to §32
7. **Notifications** — **quick controls (4):** "Enable all website" · "Disable optional website" · "Enable all email" · "Disable all email"; per-category rows with **Category · Website switch (mandatory-locked) · Email switch · Delivery select (Immediate / Daily digest / Weekly digest / Monthly digest / Never)**
8. **Appearance**
9. **Data Usage** — stored records breakdown; **Recycle Bin** with Refresh, per-item **Restore** and **Delete permanently**
10. **Application Guide** — per item: title, detail, "Open" route
11. **About** — **App Version** · **Release Notes** · **Privacy Policy** (View) · **Terms & Conditions** (View) · **Last legal acceptance** · **Accepted document version**

**Flutter sections:** **My Account** · **Plan & Storage** · **Billing** (billing-period dropdown Monthly / "6 Months · pay for 5" / "Yearly · pay for 10"; test-mode note; "Switch to {tier}"; "Billing portal"; "Cancel plan?" confirm) · **Notifications** · **Recycle bin** (Restore, "Delete '{title}' forever?") · **Security** (**Professional code** + Update; **Current password** · **New password** · **Confirm new password**) · **Account deletion**.

**Gap:**
- Missing: **Appearance** section (theme).
- Missing: **Application Guide** section entirely.
- Missing: **About** section — App Version, Release Notes, **Privacy Policy link**, **Terms & Conditions link**, **Last legal acceptance**, **Accepted document version**. Combined with §7/§10, Flutter has no legal surface anywhere.
- Missing: notification **quick controls (4 bulk buttons)** — Flutter has a popup menu with 3 options, close but not equivalent ("Disable optional website" vs "Turn off optional in-app" is fine; "Enable all email" has no counterpart).
- Missing: **"Save N%" cycle savings badges** on plans.
- Missing: **"Step down to:" downgrade target radio** (pro vs starter_free).
- Missing: **"Renews {date}"** and **"Cancellation scheduled — access ends {date}"** membership detail.
- Missing: **Current Usage breakdown (Groups / Templates / Resources / Storage)** as discrete rows.
- Difference: Flutter's password change asks for the **current password**; Angular asks only for new + confirm. Reconcile.

---

## 32. Payment Settings (`/professional` settings → payments)

- **Angular:** `professional/professional-payment-settings/professional-payment-settings.component.html` (311 lines) + `.ts` (387 lines)
- **Flutter:** settings block inside `professional_payments_page.dart`
- **Status:** **Partially built**

**Angular fields (full list):**
1. **Reporting Currency** — "Reporting currency" select + confirm
2. **"Complete Transaction History"** toggle (client-visible history)
3. **Manual Payment Methods** — list with **Edit** · **"Preview as Client"** · **Delete**; "Add Payment Method"
4. Method form: **Category** * · **Display label (client sees this)** * · **Supported currency** (or "Any currency") · **Country / region** * · **QR code image (optional)** upload · **Internal name (private)** · **Payment instructions for the client** · **Internal notes (private)** · Cancel/Save
5. **Integrated Payments** section
6. **Payment Disclosures** section

**Flutter fields:** **"Payment tracking"** switch ("Show the revenue dashboard and summaries") · **"Client payment history"** switch ("Let clients see their own payment records") · **Reporting currency** dropdown; method form: **Name (e.g. My UPI)** · **Type** · **Details clients see** · **Instructions (optional)**; "Delete {method}?" confirm.

**Gap:**
- Missing method fields: **Supported currency**, **Country / region**, **QR code image upload**, **Internal notes (private)**. (Flutter's "Name" maps to internal name and "Details clients see" to display label, but the currency/country/QR/notes fields have no home.)
- Missing: **"Preview as Client"** action.
- Missing: **Integrated Payments** and **Payment Disclosures** sections.
- Missing: **Edit** on existing methods (Flutter shows add + delete).

---

## 33. Subscription Payment (`/professional/subscription-payment`)

- **Angular:** `professional/professional-subscription-payment/professional-subscription-payment.component.ts` (202 lines, TS-rendered)
- **Flutter:** **none** (Flutter's Billing section opens the external billing portal instead)
- **Status:** **Missing entirely**

**Gap:** No in-app checkout/subscription confirmation screen. Flutter routes through "Billing portal", which may be acceptable (and is safer for app-store policy), but it is a behavioural difference the owner should confirm rather than a like-for-like page.

---

## 34. Support / Feedback (`shared/support-incidents`)

- **Angular:** `shared/support-incidents/support-incidents.component.html` + `.ts` (186 lines)
- **Flutter:** `lib/features/support/support_incidents_page.dart` (430 lines)
- **Status:** **Fully matches** (minor copy differences)

**Angular fields:** H2 "Feedback and bug reports"; **"New request"** (disabled when `!canCreate`); form — **Request type** select · **Page or feature** (placeholder "For example: Dashboard or Templates") · **Subject** (maxlength 180) · **Description** (rows 5, maxlength 5000) · **Screenshot (optional)** (png/jpeg/webp) · Cancel/Submit; incident list with subject, status, **"Reply to support"** (when waiting_for_user), **"Reopen request"** (when resolved/closed), **follow-up textarea** + Cancel/"Send response".

**Flutter fields:** "Report a bug or send feedback"; **Request type** · **Subject** · **Description** · **Screenshot**; "Your requests (N)"; **"Reply to support"** field + "Send reply"; **"Reopen"**.

**Gap:** Only missing the **"Page or feature"** field. Otherwise at parity.

---

# PART 3 — Client Area

---

## 35. Client Shell / Navigation

- **Angular:** `shared/client-portal-nav/client-portal-nav.component.html` + `shared/client-page-shell/*`
- **Flutter:** `client_tabs_shell.dart` + `client_more_page.dart`
- **Status:** **Built but fields differ**

**Angular nav (5):** Dashboard · Templates · Meetings & Reminders · Professional · Settings · plus Sign Out.

**Flutter tabs (4):** Dashboard · Programs · Professional · More. **More menu (5):** Settings · Help & Support · Meetings · Payments · Notifications.

**Gap:** Meetings is demoted from a primary nav item to a More-menu entry. Angular has no Payments nav item (payments live under the Professional tab); Flutter promotes it to More. Net: navigable parity, different hierarchy — worth an explicit owner decision.

---

## 36. Client Dashboard (`/client/dashboard`)

- **Angular:** `client/client-dashboard/client-dashboard.component.html` (94 lines) + `.ts` (131 lines)
- **Flutter:** `client_dashboard_page.dart` (318 lines)
- **Status:** **Partially built**

**Angular content:**
- Header action: **"Open Templates"**
- **KPI grid (5):** Current Check-in Streak (N days / "Consecutive active days") · **30-Day Consistency** (% / "N of the last 30 days") · Recent Check-ins (`entries_last_30_days` / "N submitted this week") · Active Templates (`active_templates` / "N lifetime entries") · **Schedules Completed** (`completed_schedules_last_30` / "During the last 30 days")
- **Focus strip:** "Next focus" (overdue count / due-24h count / "You are up to date"); "Last check-in" date; **"Record a Check-in"** button
- **Meetings & Reminders panel:** "Open All"; **pending requests** ("Waiting for professional approval") and **upcoming meetings** ("Confirmed"), each with title + full datetime; empty "No pending or upcoming meetings."
- **Reminder preview panel** (visibleRows=6): overdue count + "N pending"; **group headers** ("Overdue schedules" / "Upcoming schedules" + counts); per row — **title**, "Professional-scheduled activity", **date**, **time (or "Time not set")**, **status pill**, **"Open Details"**; empty "No upcoming schedules."
- **Template Analytics:** per template — name + chart stack; empty "Submit template entries to see analytics here."

**Flutter content:** AppBar "Dashboard"; **"Your consistency"** KPIs (4): **Streak · Consistency · Entries · Active days**; schedule rows with `StatusPill('Done'|'Due')`; **"Your templates"** section.

**Gap:**
- KPI mismatch: missing **Active Templates** and **Schedules Completed**; Flutter's "Active days" is not an Angular KPI. Also missing every KPI **caption** ("Consecutive active days", "N of the last 30 days", "N submitted this week", "N lifetime entries").
- Missing: **focus strip** — "Next focus", "Last check-in", and the **"Record a Check-in"** primary CTA.
- Missing: **Meetings & Reminders panel** with pending/confirmed states (Flutter's meetings live in the More tab).
- Missing on schedule rows: **date**, **time**, **"Professional-scheduled activity"** label, **"Open Details"** action, and the **overdue/upcoming group headers with counts**.
- Missing: **Template Analytics** chart section on the dashboard (charts exist under Programs → Progress instead).

---

## 37. Client Settings (`/client/settings`, `/client/profile?tab=details`)

- **Angular:** `client/client-profile/client-profile.component.html` lines 24–172 (details tab) + `.ts` (711 lines)
- **Flutter:** `client_settings_page.dart` (601 lines)
- **Status:** **Built but fields differ**

**Angular fields (full list):**
- **Settings sub-tabs** (`tabs` array)
- **Client Information card:** photo/initials; **9 read-only rows** — **First Name · Middle Name · Last Name · Username · Email · Group · Joined Date · Status · Reference ID**; **"Edit Profile"**
- **Registration Details** section with the change-request state and **professional note** display
- **Edit form:** every editable registration field by type (select with placeholder, input, textarea) with required markers; **"Note to your professional (optional)"** (placeholder "Explain what changed"); Cancel / Submit
- **Security card:** "Change your password. You will be signed out after it is updated."; **New password** · **Confirm new password**; "Change Password" / "Changing..."
- **Privacy & Legal card:** **Privacy Policy** (View) · **Terms & Conditions** (View) · **Last legal acceptance** · **Accepted document version**
- **Delete Account card:** "Deletion requires professional approval and appears in their action queue."; **"Reason for your professional (optional)"** textarea; **"Request Account Deletion"** / "Sending..."; **"Withdraw Request"** when pending

**Flutter fields:** AppBar "Settings"; **"Change photo"**; **"Your details"** section (keys: `first_name` "First name", `last_name` "Last name", `email` "Email"); **"Request an edit"** with per-field inputs + **"Note to your professional (optional)"** + Cancel; **"Password"** — **Current password** · **New password** · **Confirm new password**; **"Account"** — "Delete your account", "Request deletion" dialog with a note field, "Withdraw request".

**Gap:**
- **Client Information: 9 rows → 3.** Missing: **Middle Name**, **Username**, **Group**, **Joined Date**, **Status**, **Reference ID**.
- **Missing: the entire Privacy & Legal card** — Privacy Policy link, Terms link, last legal acceptance, accepted document version.
- Missing: **professional note** display on a reviewed change request.
- Difference: Flutter requires the **current password** to change password; Angular does not, and Angular explicitly signs the client out afterwards.
- Missing: the "you will be signed out" warning.

---

## 38. Client Templates / Programs (`/client/profile?tab=templates`)

- **Angular:** `client/client-profile/client-profile.component.html` lines 351–585
- **Flutter:** `client_programs_page.dart` (573 lines) + `client_progress_section.dart` (324 lines) + `client_template_resources_page.dart` (132 lines)
- **Status:** **Partially built**

**Angular content:**
- **Template chips** to switch between assigned templates (when >1)
- Per template: name; **template tabs** (`templateTab` array — overview/resources/entry/progress)
- **Stats** — per-field `stat.label` + value; empty "No submitted data yet"
- **Resources** section
- **Entry form:** **Entry date** · **Entry time** · **every template field by type** (text with placeholder "Your update", yes/no select, dropdown select, rating select from `ratingSteps`, number/text) · **"How are you feeling? (optional)"** textarea (placeholder "Anything your professional should know today"); **"Clear Form"**; Submit
- **Review dialog:** "Confirm your entry" / "Confirm updated entry"; **"Go Back"** · Confirm
- **Recent Entries:** "N total"; per entry — date, **"View"** button, **"Edit"** button (when editable)
- **Progress** section: per record — date, title, notes
- Empty: "No templates assigned yet"

**Flutter content:** AppBar "Programs"; segments **Progress / Program / Log / Resources**; **"Log an entry"** form (fields by type: yes/no segments, rating chips, text/number with placeholder) + **"Note (optional)"** + **"Clear"**; **"History (N)"**; Progress section with **Overview / Charts / History** sub-tabs and **7d / 30d / 90d / All** ranges.

**Gap:**
- Missing: **Entry date** and **Entry time** inputs — a client cannot backdate a check-in on mobile.
- Missing: **confirmation review dialog** before submitting ("Confirm your entry" / "Go Back").
- Missing: **View** and **Edit** actions on past entries.
- Missing: the **"How are you feeling?"** framing (Flutter labels it "Note (optional)") and its guiding placeholder.
- Missing: **per-field stats labels** in the client-facing overview (Flutter shows "N entries" style summaries).
- Missing: **multi-template chip switcher** (Flutter uses a different selection mechanism inside Programs).
- Flutter *adds* Charts and date-range filtering on the client side — Angular's client view has stats but a thinner chart story. Keep.

---

## 39. Client → Professional Tab (`/client/profile?tab=professional`)

- **Angular:** `client/client-profile/client-profile.component.html` lines 173–350
- **Flutter:** `client_professional_page.dart` (514 lines)
- **Status:** **Partially built**

**Angular content:**
- **Professional sub-tabs** + an **"Additional Details"** tab
- **Profile view:** professional name; **About**; **Professional Summary (4 rows):** Professional type · Experience (N years) · Specializations · Languages — each with "Not added" fallback; **Training Style**; **Certification (3 rows):** Name · Issued by · Year; **Images** gallery (figure caption = title + category); **Links**; fallback "Professional details are not available yet."
- **Payments** section ("Payment requests from your professional and how to pay them.")
- **Additional Details** section: items with **"Open"** action for links
- **Chat** (via `app-chat-panel`, client mode)

**Flutter content:** AppBar "Professional"; segments **Profile / Chat**; sections **About · Professional details · Training style · Certification (with "View certificate")· Gallery · Links · "Shared with you"**; chat composer ("Message…").

**Gap:**
- Missing: **Professional Summary as 4 labelled rows** (Professional type / Experience / Specializations / Languages) — Flutter renders a generic details block.
- Missing: **Certification broken into Name / Issued by / Year**.
- Missing: **image captions (title + category)** in the gallery.
- Missing: **Payments entry point from this tab** (Flutter moves payments to the More menu — see §35).
- Missing: **"Open" action on additional-detail links**.
- **Chat: missing image attachment**, **safety caution banner**, **message count**, **sender labels** — same as §23.
- Flutter *adds* "View certificate" (good).

---

## 40. Client Meetings & Reminders (`/client/meetings`)

- **Angular:** `client/client-meetings/client-meetings.component.html` (161 lines) + `.ts` (178 lines)
- **Flutter:** `client_meetings_page.dart` (159 lines)
- **Status:** **Partially built**

**Angular content:**
- Header action: **"Request a Meeting"**
- **Pending Professional Approval** section: title, start–end, notes, **"Waiting for your professional to respond"** pill
- **Upcoming** section: title, **group-session guest list**, start–end, notes, **response pill** ("You're going" / "You declined" / "Awaiting your response"); actions **Join Link** · **Accept** · **Decline** (each disabled per current response)
- **Reminders** section: title, date + time, notes, **status pill with overdue styling**; empty "No pending reminders."
- **Past & Cancelled** section with status pills
- **Request Meeting modal:** **Date** (min today) · **Length** select (15 / 30 minutes) · **Meeting title** (maxlength 180) · **Notes for your professional** (maxlength 2000) · **"Available times ({timezone})"** slot buttons · loading state · **"Your professional has not added meeting availability yet…"** helper · "No available times on this date. Try another date." · Cancel / "Send Request"

**Flutter content:** AppBar "Meetings"; "Response: {status}"; **Accept** · **Decline** · **Join meeting** · **"Add to calendar"**; error "The calendar invite could not be opened."

**Gap:**
- **Missing: the entire "Request a Meeting" flow** — date, length, title, notes, timezone-labelled slot picker, the no-availability helper text, and the empty-slots message. Clients cannot request a meeting from mobile at all.
- Missing: **Pending Professional Approval** section.
- Missing: **Reminders** section (title / date / time / notes / overdue status).
- Missing: **Past & Cancelled** section.
- Missing: **group-session guest list**.
- Missing: human-readable **response pills** ("You're going" / "You declined" / "Awaiting your response") — Flutter prints the raw status string.
- Flutter *adds* "Add to calendar" (good).

---

## 41. Client Payments (`/client/payments`)

- **Angular:** `client/client-payments/client-payments.component.html` → `shared/client-payments-panel/*` (76 + 72 lines)
- **Flutter:** `client_payments_page.dart` (529 lines)
- **Status:** **Partially built**

**Angular content:** **View tabs (2):** Payment Requests / Activity; **"Needs your attention"** section with request cards (**unread styling**) linking to the detail page; **"Completed Payments"** section with muted cards; **"Payment Activity"** feed with empty "No payment activity yet."

**Flutter content:** AppBar "Payments"; request list with due date, "From {professionalName}"; navigates to a detail page.

**Gap:**
- Missing: **Activity tab / payment activity feed**.
- Missing: **unread indicator** on requests needing attention.
- Missing: explicit **"Needs your attention"** vs **"Completed Payments"** grouping.

---

## 42. Client Payment Request Detail (`/client/payments/requests/:requestId`)

- **Angular:** `client/client-payment-request-detail/client-payment-request-detail.component.html` (229 lines) + `.ts` (147 lines)
- **Flutter:** `ClientPaymentRequestDetailPage` inside `client_payments_page.dart`
- **Status:** **Partially built**

**Angular fields (full list):**
1. Back to Payments
2. Request header: **title**, amount/currency/due/status
3. **Payment Instructions** section — per shared method, expandable instructions
4. **"Transactions for {request_id}"** history: per proof — details plus **"Open / Print Receipt"** link to the confirmation route
5. **"Add another transaction"** button
6. **Submit Payment Proof** form:
   - **Transaction ID / reference** (placeholder "e.g. UPI ref or bank reference")
   - **Amount paid** *
   - **Currency** *
   - **Payment date** *
   - **Method used** (select over shared methods)
   - **Proof screenshot or document** (file)
   - **Note (optional)** (placeholder "Anything your professional should know")
   - **Confirmation checkbox:** "I confirm that the information submitted is accurate and that the payment was completed using the selected external payment method."
   - Submit

**Flutter fields:** AppBar "Payment request"; "Submit proof"; **Due {date}**, **From {professionalName}**; **"How to pay"** section; **"Your proofs"** list (Ref, professional note); copy action; proof form — **Transaction reference** · **Amount paid ({currency})** · **Method used** · **"Paid on {date}"** picker · **Note (optional)** · **"I confirm these details are accurate"** checkbox.

**Gap:**
- Missing: **Currency** selector on the proof form (Flutter hard-binds to the requested currency).
- Missing: **proof file/screenshot upload** — a client cannot attach payment evidence from mobile, which is the core purpose of the proof workflow.
- Missing: **"Open / Print Receipt"** link per accepted proof.
- Missing: **"Add another transaction"** affordance for partial payments.
- Weaker consent copy: Flutter's "I confirm these details are accurate" drops the "…and that the payment was completed using the selected external payment method" clause.

---

## 43. Payment Confirmation / Receipt (`/client/payments/records/:recordId/confirmation`, `/professional/payments/records/:recordId/confirmation`)

- **Angular:** `shared/payment-confirmation/payment-confirmation.component.html` (72 lines) + `.ts` (64 lines) — shared by both audiences via route `data.audience`
- **Flutter:** **none**
- **Status:** **Missing entirely**

**Gap:** No printable/viewable payment receipt on mobile for either role. Referenced from §42 ("Open / Print Receipt"), so this gap compounds that one.

---

# Appendix A — Tables and multi-field forms, side by side

For the mobile-column-budget decision. "Ang" = Angular column count, "Flt" = fields actually rendered by Flutter today.

| Page | Table / form | Ang | Flt | Angular columns (in order) |
| --- | --- | --- | --- | --- |
| Clients list | Client List | **8** | 3 | #, Client Name, Email, Group, Username, Status, Joined On, Actions |
| Group detail | Approved Users | **7** | 3 | #, Client Name, Email, Username, Status, Joined On, Actions |
| Forms & Groups | Form Requests | **7** | 2 | #, Applicant Name, Email, Submitted On, Reference ID, Group, Actions |
| Dashboard | Schedules | **7** | 2 | Client, Schedule Title, Date, Time, When, Status, Actions |
| Dashboard | Client Account Requests | **6** | 3 | Client, Group, Requested, Request, Client Note, Action |
| Dashboard | Payments — Needs Action | **6** | 2 | Client, Title, Amount, Due, Status, Actions |
| Client template | Data Entries | **6** | 2 | Date, Time, Values, Note, Status, Actions |
| Dashboard | Recent Transactions | **5** | 0 | Client, Amount, Received, Status, Actions |
| Client payments tab | Manual Payment Log | **4** | 0 | Payment, Reference, Received, Status |
| Group import | Result — Created | **4** | 0 | Row, Client, Email, Portal Access |
| Group import | Mapping preview | **3** | 0 | File Column, Maps To, Match |
| Client profile | Change request diff | **3** | 0 | Field, Current, Requested |
| Group import | Result — Failed | **2** | 0 | Row, Reason |
| Client settings | Client Information rows | **9** | 3 | First Name, Middle Name, Last Name, Username, Email, Group, Joined Date, Status, Reference ID |
| Client profile (pro) | Account & Access dialog | **9** | 0 | Portal Access, Username, Email, Group, Reference ID, Submitted On, Joined On, Status, Password |
| Profile setup | Setup form inputs | **13** | 11 | photo, first, middle, last, code, gender, birth month, birth year, country, state, headline, about me, save |
| Professional profile | Full profile form | **22** | ~10 | photo, first, last, phone, gender, b.month, b.year, country, state, headline, about, prof type, years, specializations, languages, training style, cert name, cert issuer, cert year, cert file, images[], links[] |

---

# Appendix B — Priority ordering (suggested)

**P0 — blocks real users**
1. Professional forgot password (§5) — no recovery path on mobile
2. Form Request Detail "Submitted answers" (§20) — approving applicants blind
3. Client profile change-request diff table (§23) — approving edits blind
4. Client payment proof **file upload** (§42) — proof workflow is unusable without it
5. Legal consent gates + legal document links (§7, §10, §31, §37) — compliance and app-store surface

**P1 — significant missing workflows**
6. Schedule: book a new meeting + month calendar + days off (§28)
7. Client: request a meeting (§40)
8. Group CSV import (§19)
9. Manual client create: dynamic registration fields + portal-access modes (§21)
10. Client template: Data Entries table, Share Resources, Progress tab, exports (§24)
11. Chat image attachments + safety banner (§23, §39)

**P2 — column/field density decisions**
12. Every table in Appendix A — pick the surviving 3–5 columns and decide where the rest live
13. Profile setup: headline + about me; country/state as pickers (§6)
14. Professional profile: certifications, images, links, phone (§30)

**P3 — polish and parity**
15. Google Sign-In (§3, §4); password-requirements checklist; OTP resend countdown
16. Locked/lock-badge treatment and drag-to-reorder across Templates, Groups, Resources
17. Dashboard onboarding panel, plan line, usage captions, custom revenue range
