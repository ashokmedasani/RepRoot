# frontend/src/app/app.routes.ts

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

## Future improvement notes

Add route guards once dashboard and other protected pages are implemented.
