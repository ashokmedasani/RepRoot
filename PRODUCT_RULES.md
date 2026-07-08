# Product Rules

This document is the source of truth for the Trainer & Client Management Platform.

Before generating or modifying code, every AI assistant or developer must read this file first and follow the decisions recorded here. When a decision is finalized, add it here before continuing development.

## Project Identity

- Temporary application name: Trainer Management Platform.
- Final branding is not decided yet.
- The product is a production-quality Trainer & Client Management Platform.
- The web application is the first implementation target.
- The mobile application will be planned only after the web version is stable, tested, and approved.

## Confirmed Technology Stack

- Frontend: Angular, latest stable version.
- Backend: Django.
- API framework: Django REST Framework.
- Database: PostgreSQL for local development.
- Version control: Git and GitHub.
- Deployment sequence: local development first, Render or Railway later for testing, production hosting later.

## Project Structure

- `frontend/`: Angular web application.
- `backend/`: Django and Django REST Framework backend.
- `Documentation/`: mirrored documentation for created or modified project files.
- `PRODUCT_RULES.md`: source of truth for product and architecture decisions.

Frontend and backend must remain separated so Angular and Django do not become tangled as the project grows.

## Development Workflow

Development must happen page by page, module by module, and feature by feature.

For every page:

1. Understand the business purpose.
2. Design the UI.
3. Wait for review.
4. Implement the frontend.
5. Wait for approval.
6. Connect the backend.
7. Wait for approval.
8. Connect the database.
9. Test.
10. Move to the next page only after approval.

Do not build Page 2 until Page 1 is reviewed and approved.

## Current Development Status

- UI design direction: finalized.
- Technology stack: finalized.
- Database: PostgreSQL.
- Version control target: GitHub.
- Development style: page by page.
- Current task: Page 2 backend and database connection.

## Page 1 Status

- Page 1 name: Landing / Project Introduction Page.
- Page 1 business purpose: explain the platform idea and provide a clear starting point.
- Page 1 temporary app name: CoachFlow Studio.
- Page 1 UI design: premium SaaS landing page with hero, platform overview cards, trainer capability cards, client capability cards, and extendable theme switching.
- Page 1 frontend implementation: completed for review.
- Page 1 backend connection: not started.
- Page 1 database connection: not started.
- Page 1 testing: frontend production build completed successfully; local HTTP check completed successfully.

Page 1 must not include dashboard, backend, database, authentication logic, or Page 2 implementation.

The Page 1 primary button text is `Let's Start`. It routes to the Portal page at `/portal`.

The `/portal` route is the Page 2 Portal route. The old `/trainer-client-login` route redirects to `/portal` for compatibility.

Page 2 future scope:

- Trainer Login.
- Trainer Signup.
- Client Login.

Trainer signup is a global trainer signup page. Login will work based on the trainer account created during signup. Client login will be created later after a trainer approves and creates a client profile.

## Page 2 Status

- Page 2 name: Portal.
- Page 2 route: `/portal`.
- Page 2 frontend design: two access boxes under Client Management.
- Page 2 access boxes: Trainer and Client Portal.
- Trainer box routes directly to `/trainer/login`.
- Trainer Access page shows separate rounded boxes for Login and Signup.
- Trainer Login route: `/trainer/login`.
- Trainer Signup route: `/trainer/signup`.
- Trainer Forgot Password route: `/trainer/forgot-password`.
- Old `/trainer-login` and `/trainer-signup` routes redirect to the new route format.
- Trainer Login and Trainer Signup are separate pages, not panels on the Client Management page.
- Back buttons on access/login/signup pages sit in the top-right corner.
- Login panel accepts username or email plus password.
- Signup page includes email ID, OTP verification, password, first name, optional middle name, last name, username, and username verification.
- All signup fields are mandatory except middle name.
- Signup username appears above Email ID and must be verified before account creation.
- Username verification checks the database and displays the selected username as available, for example `ashok is available.`
- Email verification uses Django console email for free local testing. The OTP prints in the backend terminal.
- Signup OTP field label is `OTP`.
- Signup email must be checked against the database before OTP can be sent. If the email already exists, show guidance to try Login or Forgot Password.
- After a signup OTP is sent, the Send OTP button is disabled and remains labeled `Send OTP`.
- Signup resend appears as a separate link below the email field after the OTP guidance text. It is enabled after 30 seconds.
- Backend OTP resend is also limited to once every 30 seconds per email and purpose.
- OTP verification allows up to five failed attempts before the current OTP is invalidated.
- Signup must show helper text telling the trainer that the OTP was sent to email and must be submitted for verification.
- Signup email verification button must show `Verified` after backend verification succeeds, or `Not verified. Try again` after failed verification.
- Wrong signup OTP displays under the OTP field: `OTP is not verified. Please try again.`
- Signup password and confirm password are separate mandatory fields.
- Signup password requires at least 8 characters and 1 special character.
- Confirm Password must match Password.
- Signup errors must display beside the specific failed field when the backend identifies a field. Unknown signup failures must say `Please refresh and try again.`
- After successful trainer signup, the signup form state is cleared, no auth token is stored, and the user is redirected to `/trainer/login`.
- Trainer Login displays a top success notice after signup: `Trainer account created successfully. Please login now.`
- Username verification is frontend-only for now and checks reserved names plus accounts created in the current browser session.
- Login verification is frontend-only for now and validates against preview accounts created in the current browser session.
- Client Portal box displays future-client-login guidance only.
- Page 2 backend connection: implemented for trainer username check, trainer signup, and trainer login.
- Page 2 database connection: PostgreSQL-ready Django models and migrations implemented for trainer profile data.
- Page 2 real authentication: implemented for trainer signup/login using Django auth and DRF token authentication.
- Page 2 frontend connects to backend at `http://127.0.0.1:8000/api/accounts`.
- Trainer signup creates a Django `User`, linked `TrainerProfile`, and auth token.
- Trainer login accepts username or email plus password and returns an auth token.
- Trainer password reset uses the trainer email address, a six-digit OTP, and a temporary reset token.
- Password reset OTP uses Django console email for free local testing and prints in the backend terminal.
- Forgot Password checks the database before sending OTP. If no trainer account exists, show Signup and Login guidance.
- Forgot Password OTP field label is `OTP`.
- Wrong Forgot Password OTP displays under the OTP field: `OTP is not verified. Please try again.`
- Forgot Password password reset requires at least 8 characters and 1 special character.
- Forgot Password Confirm Password must match Password.
- Forgot Password Send OTP button remains labeled `Send OTP` and is disabled after sending.
- Forgot Password resend appears as a separate link below the email field and is enabled after 30 seconds.
- After successful password reset, the reset form state is cleared and the user is redirected to `/trainer/login` with a top login notice.
- Trainer profile stores optional middle name from signup. Existing database support for birth month and birth year can remain for backward compatibility, but the signup page does not ask for either field.
- Client login remains future scope and must not be implemented until the trainer approval/client creation workflow is approved.
- Trainer login checks whether profile setup is completed after authentication.
- If trainer profile setup is incomplete, route to `/trainer/profile-setup`.
- If trainer profile setup is complete, route to `/trainer/profile`.
- Trainer Profile Setup is a required first-login page and stores profile photo, first name, last name, birth month, birth year, gender, country, state/region, professional headline, and about me.
- Trainer Profile is the main trainer profile page and stores basic profile, professional details, one certification entry, portfolio media fields, and social links.
- Trainer profile country and state/region dropdowns use global country/state data from the frontend `country-state-city` package.
- Dashboard is not implemented yet.

## Tracking Templates, References, Client Portal, Chat, and Insights

- Tracking templates are trainer-level, not group-level. One set of templates is available across all of a trainer's groups.
- A trainer can have at most 5 templates.
- Three standard templates ship with the platform and can be adopted with one click: Nutrition Details, Vitamins & Supplements, and Daily Progress Check-in. Adopted templates count toward the 5-template limit and can be customized.
- Nothing in a template is mandatory for clients. Template fields never carry required flags, and a missed day never blocks the client or the app.
- Templates are managed only in the dedicated Templates section (`/trainer/templates`). Group pages do not show a templates tab.
- Templates are assigned per client. Assignments can be added or removed at any time; unassigning or deleting a template never deletes the client's past entries (entries keep a template-name snapshot).
- The trainer References Library is stored server-side (categories with subcategories, plus references). Video references must be YouTube links and are streamed inside the app; PDFs and images upload as real files to Django media storage. Video file uploads are not allowed.
- References are NOT attached to templates. They are shared per client at assignment time: when a trainer assigns a template to a client, they pick which references to share (a Share References dialog on the assignment, editable anytime), so each client receives only the resources relevant to their goal.
- Clients authenticate with a real portal token (`Authorization: ClientToken <key>` via the `ClientAuthToken` model), stored in sessionStorage. Client login returns the token.
- Clients with a temporary password are routed to `/client/change-password`; changing the password clears `must_change_password`.
- The client portal (`/client/profile`) has four sections: My Templates (fill in and submit entries, one entry per template per date with same-day upsert), My Details (registration and lead-form answers, read-only), Resources (attached references with in-app YouTube streaming), and Trainer Chat.
- Client tracking entries appear in the trainer's client profile, and the trainer can edit any entry at any time; trainer edits are flagged `edited_by_trainer`.
- Trainer-client chat is stored in the backend (`ChatMessage`) and polled over REST every 5 seconds while a chat panel is open. No websockets in Version 1.
- The trainer client profile consolidates identity and password reset into a single Account & Access dialog and includes an Insights section computed from entries: 30-day check-in consistency, numeric field trends, and recent client notes by date.

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

The application must support multiple extendable themes, not only light and dark modes.

The initial theme direction is:

- Main Theme: white and light blue.
- Dark.
- Green Wellness.
- Purple Premium.
- Black Gold.

Theme switching must affect:

- Backgrounds.
- Cards.
- Tables.
- Sidebar.
- Navigation.
- Buttons.
- Icons.
- Charts.
- Forms.
- Inputs.
- Dialogs.

The theme architecture must be scalable so additional themes can be added later without rewriting page logic.

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
- Local PostgreSQL setup is defined in `docker-compose.yml` with database `trainer_platform`, user `postgres`, and password `postgres`.
- Local Windows PostgreSQL 16 is installed for development with database `trainer_platform`, user `postgres`, password `postgres`, and port `5432`.

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
- Required work must be completed first.
- Suggestions must be listed separately after required work.
- Build page by page.
- Complete the current page fully before moving forward.
- Wait for approval after each required review step.
