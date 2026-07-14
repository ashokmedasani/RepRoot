# frontend/src/app/app.routes.ts

## 2026-07-13 targeted refinement

Adds Client Dashboard, manual client creation, and public group registration routes while preserving compatibility routes.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Defines Angular routes for the application.

## Why this file exists

Routes map URLs to standalone page components and keep page loading lazy.

## Page or module

Application routing.

## Important routes

- `/`: landing page.
- `/portal`: trainer/client access portal.
- `/trainer/login`: trainer login.
- `/trainer/signup`: trainer signup.
- `/trainer/forgot-password`: forgot password.
- `/trainer/profile-setup`: mandatory first-login trainer setup.
- `/trainer/profile`: Profile / Portfolio page.
- `/trainer/forms-groups`: Forms & Groups setup and management page.
- `/trainer/forms/create`: guided public lead form creation page.
- `/trainer/groups/create`: guided group creation page.
- `/trainer/groups/:groupId/client-form/create`: guided client creation form page for one group.
- `/trainer/groups/:groupId/users`: active users created under a group.
- `/public/forms/:publicSlug`: public trainer lead form page for applicants.

## Data flow

The login page redirects trainers based on profile status. Forms & Groups is a separate trainer page and does not add trainer profile checks.

## Business logic

Old trainer access routes redirect to the current route format for compatibility.

## Connected files

- `frontend/src/app/pages/trainer-login/trainer-login.component.ts`
- `frontend/src/app/pages/trainer-profile-setup/trainer-profile-setup.component.ts`
- `frontend/src/app/pages/trainer-profile/trainer-profile.component.ts`
- `frontend/src/app/pages/trainer-forms-groups/trainer-forms-groups.component.ts`
- `frontend/src/app/pages/public-lead-form/public-lead-form.component.ts`

## Protected-route behavior

Trainer portal routes require a trainer token and redirect to Trainer Login when it is absent. Client portal routes require a client token and redirect to Client Login when it is absent. The reusable guards live in `frontend/src/app/core/guards/portal-auth.guards.ts`.

## Update: templates and client portal routes

- `trainer/templates`, `trainer/templates/create`, `trainer/templates/:templateId/edit` (dedicated Templates section); the old `trainer/groups/:groupId/tracking-template/create` route redirects to `trainer/templates`.
- `client/change-password` for the forced password change after a temporary password.

## Update: dashboard and route cleanup

Added `trainer/dashboard`; the duplicate `trainer/groups/:groupId/users` route now redirects to `trainer/groups/:groupId`.

## Update

Added `trainer/clients/:clientId/templates/:assignmentId` (Template Detail page).

## 2026-07-13 visual consistency pass

Aligned this file with the shared Dashboard-style page header, portal navigation, action controls, and unclipped profile-image treatment. Verified at port 4400 with no horizontal overflow and covered by the production Angular build.

## 2026-07-13 error routes

- `/error` displays safe network, access, service, and runtime failure information.
- the final wildcard route displays the shared page with dedicated 404 content for unknown application URLs.

## 2026-07-13 Admin Portal Phase 1

Adds protected, separate routes for internal login, aggregate Dashboard, Finance, and Audit Logs. Admin routes do not reuse trainer/client portal authentication.
