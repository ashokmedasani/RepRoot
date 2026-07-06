# frontend/src/app/pages/trainer-login/trainer-login.component.ts

## What this file does

Defines the trainer login page and submits credentials to the backend.

## Why this file exists

Trainer login should be a separate page from signup and from the Client Management access selection page.

## Page or module

Trainer Login page.

## Important functions/classes/components

- `TrainerLoginComponent`: standalone login form component.
- `verifyTrainerLogin`: validates required fields and calls the backend login API.

## Data flow

Username/email and password flow from the template into the component, then into `TrainerAuthApiService`, then to Django REST Framework.

## Connected files

- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `frontend/src/app/pages/trainer-login/trainer-login.component.html`
- `frontend/src/app/pages/trainer-login/trainer-login.component.scss`

## Business logic

Login requires username/email and password. Successful login stores the backend token in `localStorage`.

## Assumptions made

Post-login dashboard routing is not approved yet, so the page shows a success message only.

## Future improvement notes

Route to the approved trainer landing page after login when that page exists.
