# Product Rules

This document is the source of truth for the Professional & Client Management Platform.

Before generating or modifying code, every AI assistant or developer must read this file first and follow the decisions recorded here. When a decision is finalized, add it here before continuing development.

## Project Identity

- Product name: **RepRoot** — a production professional & client management platform, live
  across a web portal, an Android app, and an internal Admin Portal.
- This is no longer an early-stage build. Treat every rule below marked as "still
  active" as a real constraint on a live system with real professional/client data flows,
  not a greenfield spec.

## Confirmed Technology Stack

- Web frontend: Angular (standalone components).
- Mobile: **Flutter** (`mobile_flutter/`) is the sole mobile client. The original
  Ionic/Capacitor app (`mobile/`) has been removed from the repo. iOS is unbuilt.
- Backend: Django + Django REST Framework, PostgreSQL, Redis, S3-compatible media
  storage (`django-storages`).
- Admin Portal: a third, isolated surface (`/admin-portal/*` web routes, `/api/admin/*`
  API, its own staff auth/RBAC/audit log) for internal staff — not reachable with
  professional or client credentials.
- Version control: Git and GitHub.
- Deployment: Render (`render.yaml`); local dev uses `docker-compose.yml` or a local
  PostgreSQL install.

## Project Structure

- `frontend/`: Angular web application (professional portal, client portal, Admin Portal
  pages, public landing/lead-form pages).
- `mobile_flutter/`: Flutter Android app — the only mobile client.
- `backend/`: Django + DRF backend. Key apps: `accounts` (professional/client domain logic)
  and `admin_portal` (internal staff console: dashboard, finance, audit log, support
  incidents, error/bug log).
- `Documentation/`: mirrored documentation for created or modified project files, plus
  dated CHANGELOG files and per-feature reports (e.g. `FLUTTER_PARITY_REPORT.md`).
- `PRODUCT_RULES.md`: source of truth for product and architecture decisions.

Frontend and backend must remain separated so Angular and Django do not become tangled
as the project grows.

## Development Workflow

The original methodology below (strict page-by-page, wait-for-approval-at-every-step)
was how the first few pages (Landing, Portal, Professional auth) were built and is preserved
here as the *default* for genuinely new, ambiguous product surfaces. In practice, once a
pattern is established (a new CRUD page in an existing module, a bug fix, a documented
parity gap), work has since been delivered in larger batches per explicit instruction,
including whole features end-to-end in one pass. Use judgment: unclear/new product
direction → check in before building; well-scoped, established-pattern work → build,
verify, and report back.

For a genuinely new page/module:

1. Understand the business purpose.
2. Design the UI.
3. Confirm the approach if it's ambiguous.
4. Implement frontend + backend + database together where the scope is well understood.
5. Test.
6. Report what changed.

## Current State (high level — see Documentation/ for detail)

Both professional and client roles are fully built across web and Flutter: auth (signup,
login, OTP email verification, password reset), profile setup, tracking templates,
group/client management, references library, professional-client chat, scheduling/reminders,
dashboards with analytics, and an Admin Portal (staff RBAC, audit log, support incidents,
automatic error/crash logging separated into Web and Mobile queues). Do not treat any of
this as "not implemented yet" — check the relevant `Documentation/` file or the code
itself before assuming a feature is missing.

The step-by-step build log for how the earliest pages (Landing, Portal) were implemented
has been removed — that detail lived here while the project was two pages long and is no
longer representative; consult `git log` and `Documentation/` for how any specific piece
was actually built. The specific, still-enforced *business rules* that were recorded
alongside that log (password/OTP behavior, routing, error copy) are kept below, not
deleted with it — they are real constraints, not status.

## Professional Authentication & Onboarding Rules (still active, verified 2026-07-18)

- Routes: Professional Login `/professional/login`, Signup `/professional/signup`, Forgot Password
  `/professional/forgot-password`. Login accepts username or email plus password.
- Signup fields: email, OTP verification, password, first name, optional middle name,
  last name, username with availability verification. All mandatory except middle name.
  Username must be verified (real backend check) before account creation.
- Email/OTP verification is backend-real (Django auth + DRF tokens), not a frontend
  placeholder. Local dev uses Django's console email backend — the OTP prints in the
  backend terminal. Production refuses to start with the console backend (see
  `EMAIL_BACKEND` guard in `config/settings.py`).
- OTP field label is `OTP`. Signup email is checked against the database before an OTP is
  sent — if the account already exists, show Login/Forgot-Password guidance instead.
- Send OTP button disables and stays labeled `Send OTP` after sending; a separate resend
  link appears below the email field, enabled after 30 seconds (backend also enforces a
  30-second resend cooldown per email+purpose — `OTP_RESEND_COOLDOWN_SECONDS`).
- OTP verification allows up to 5 failed attempts before the OTP is invalidated
  (`OTP_MAX_VERIFY_ATTEMPTS`). Wrong-OTP message: `OTP is not verified. Please try again.`
- Password + Confirm Password are separate mandatory fields; password requires at least 8
  characters and 1 special character (`validate_password_strength`), enforced identically
  for signup and password reset. Confirm Password must match Password.
- Signup field errors display beside the specific failed field when the backend
  identifies one; unknown failures show `Please refresh and try again.`
- After successful signup: form clears, no token is stored, redirect to `/professional/login`
  with the success notice `Professional account created successfully. Please login now.`
- Password reset: OTP-based (same 30s cooldown, 5-attempt limit, console email locally),
  checks the database before sending (no-account guidance to Signup/Login), same password
  rules as signup, redirects to `/professional/login` with a login notice on success.
- Post-login routing: if `profile_setup_completed` is false, route to
  `/professional/profile-setup`; otherwise `/professional/profile`.
- Professional Profile Setup (required first login) collects: photo, first/last name, birth
  month/year, gender, country, state/region, professional headline, about me. Middle name
  is stored from signup; birth month/year fields exist for backward compatibility but are
  not collected at signup itself.
- Professional Profile (ongoing profile page) covers: basic profile, professional details, one
  certification entry, portfolio media, social links. Country/state dropdowns use the
  frontend `country-state-city` package.

## Tracking Templates, References, Client Portal, Chat, and Insights

- Tracking templates are professional-level, not group-level. One set of templates is available across all of a professional's groups.
- A professional can have at most 5 templates.
- Three standard templates ship with the platform and can be adopted with one click: Nutrition Details, Vitamins & Supplements, and Daily Progress Check-in. Adopted templates count toward the 5-template limit and can be customized.
- Nothing in a template is mandatory for clients. Template fields never carry required flags, and a missed day never blocks the client or the app.
- Templates are managed only in the dedicated Templates section (`/professional/templates`). Group pages do not show a templates tab.
- Templates are assigned per client. Assignments can be added or removed at any time; unassigning or deleting a template never deletes the client's past entries (entries keep a template-name snapshot).
- The professional References Library is stored server-side (categories with subcategories, plus references). Video references must be YouTube links and are streamed inside the app; PDFs and images upload as real files to Django media storage. Video file uploads are not allowed.
- References are NOT attached to templates. They are shared per client at assignment time: when a professional assigns a template to a client, they pick which references to share (a Share References dialog on the assignment, editable anytime), so each client receives only the resources relevant to their goal.
- Clients authenticate with a real portal token (`Authorization: ClientToken <key>` via the `ClientAuthToken` model), stored in sessionStorage. Client login returns the token.
- Clients with a temporary password are routed to `/client/change-password`; changing the password clears `must_change_password`.
- The client portal (`/client/profile`) has four sections: My Templates (fill in and submit entries, one entry per template per date with same-day upsert), My Details (registration and lead-form answers, read-only), Resources (attached references with in-app YouTube streaming), and Professional Chat.
- Client tracking entries appear in the professional's client profile, and the professional can edit any entry at any time; professional edits are flagged `edited_by_professional`.
- Professional-client chat is stored in the backend (`ChatMessage`) and polled over REST every 5 seconds while a chat panel is open. No websockets in Version 1.
- The professional client profile consolidates identity and password reset into a single Account & Access dialog and includes an Insights section computed from entries: 30-day check-in consistency, numeric field trends, and recent client notes by date.

## Professional Code (client login)

- Each professional chooses a unique Professional Code during profile setup (first-login, required field, with a `?` tooltip explaining its purpose). It is editable later in Account Settings and shown there to share with clients.
- Codes are 4-20 characters (letters, numbers, hyphens, underscores), stored uppercased, unique across professionals.
- Client login requires Professional Code + Username + Password. The code identifies the professional, then the client's username/password are matched within that professional's clients (client usernames are only unique per professional, so the code disambiguates).
- Professional signup does NOT ask for the code; it is set at profile setup.

## Redesign Decisions (FitCoach-style)

- The professional workspace uses a fixed left sidebar (brand, icon navigation, Sign Out at bottom); it collapses to a horizontal bar on small screens.
- A real Dashboard page exists at `/professional/dashboard` with stat tiles and quick lists.
- Compact design tokens: panel radius 0.75rem, panel padding 1rem, subtle shadows (`--app-shadow-sm`), page h1 1.45rem. Heavy blur shadows are retired.
- The client profile and the template detail are two separate pages. The client profile (`/professional/clients/:id`) is a single column: identity card, private Professional Notes (stored on `ClientAccess.professional_notes`, never sent to the client portal), clickable Assigned Templates, Client Activity stats (entries this month, last entry, streak, completion %), and chat. Clicking an assigned template opens the Template Detail page (`/professional/clients/:id/templates/:assignmentId`) with a Back button, Share References, Start New Entry, and Overview / Data Entries / Progress tabs.
- Professionals can record an entry on behalf of a client (marked as professional-recorded, upserts by date).
- Every password field uses the shared `app-password-input` component with a show/hide eye toggle.
- Duplicate route `professional/groups/:groupId/users` redirects to the group detail route.

## UI Design Philosophy

The application must feel like a premium SaaS application:

- Modern.
- Minimal.
- Professional.
- Highly responsive.
- Fast.
- Accessible.
- Production-ready on every page.

Use:

- Cards.
- Tables.
- Responsive forms.
- Drawers.
- Dialogs.
- Modals.
- Progress cards.
- Statistics cards.
- Clean navigation.

Avoid clutter. Maintain consistent spacing, typography, and colors.

## Theme System

**Superseded.** The original plan below (5 switchable brand themes) was never built and
is not the current direction — only light/dark mode exist, driven by a single fixed
brand token set (`--app-*` CSS variables on web, `AppTokens`/`AppColors` in Flutter). The
governing rule now is: **never change the brand colors**; new pages and components
consume the existing tokens rather than introducing new palettes. Light/dark must
continue to affect backgrounds, cards, tables, sidebar/navigation, buttons, icons,
charts, forms, inputs, and dialogs — that part of the original intent stands, just
without the multi-brand-theme switcher.

<details>
<summary>Original (unbuilt) multi-theme plan, kept for history</summary>

- Main Theme: white and light blue.
- Dark.
- Green Wellness.
- Purple Premium.
- Black Gold.

</details>

## Architecture Rules

- Follow modular architecture.
- Frontend modules must be independent.
- Backend modules must be independent.
- API structure must remain scalable.
- Future AI modules must be able to plug into the existing architecture without major changes.
- Do not create future modules unless explicitly instructed.
- Do not assume future requirements.
- Do not over-engineer.
- Ask for clarification when business logic is unclear.

## Code Quality Rules

- Write clean, production-ready code.
- Separate concerns properly.
- Prefer reusable components, services, APIs, and models.
- Avoid duplicated logic.
- Document important modules.
- Preserve scalability, maintainability, and readability.
- Confirmed requirements take priority over suggestions.
- If a requirement should be changed, explain the reason and wait for approval before changing it.

## Database Rules

- Use PostgreSQL.
- Design normalized relational tables.
- If flexible fields are required later, use PostgreSQL JSONB.
- Do not use MongoDB in Version 1.
- Local PostgreSQL setup is defined in `docker-compose.yml` with database `professional_platform`, user `postgres`, and password `postgres`.
- Local Windows PostgreSQL 16 is installed for development with database `professional_platform`, user `postgres`, password `postgres`, and port `5432`.

## Documentation Rules

Every code file created or modified must have a matching Markdown documentation file under `Documentation/` with the same structure as the actual codebase.

Example:

- Actual file: `src/app/pages/landing/landing.component.ts`
- Documentation file: `Documentation/src/app/pages/landing/landing.component.md`

Each documentation file must explain:

- What the code file does.
- Why the file exists.
- What page or module it belongs to.
- Important functions, classes, or components.
- How data flows in the file.
- Which other files it connects to.
- Any business logic inside it.
- Any assumptions made.
- Future improvement notes.

Every new feature must include:

1. Working code.
2. Matching documentation.
3. A short summary of what changed.
4. Any concerns or suggestions.

## Development Control Rules

- Suggestions are allowed, but confirmed requirements must not be compromised.
- Required work must be completed first; suggestions are listed separately after it.
- Complete a page/feature fully rather than leaving half-finished work.
- For genuinely new or ambiguous product direction, check in before building — see
  "Development Workflow" above for how this has evolved from strict per-page approval
  gates to judgment-based batching for well-scoped, established-pattern work.
