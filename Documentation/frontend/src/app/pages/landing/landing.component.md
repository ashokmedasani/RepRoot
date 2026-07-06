# src/app/pages/landing/landing.component.ts

## What this file does

Defines the Page 1 landing component and the content model used by the landing page.

## Why this file exists

Page 1 introduces the platform concept and gives users a clear starting point without implementing authentication, backend, database, or dashboard features.

## Page or module

Landing / Project Introduction Page.

## Important classes and properties

- `LandingComponent`: standalone Angular page component.
- `temporaryAppName`: temporary professional app name used until final branding is approved.
- `nextPageRoute`: route for the Portal page.
- `trainerFeatures`: trainer-facing capability cards.
- `clientFeatures`: client-facing capability cards.

## Data flow

Static content arrays flow from the component class into the template. The primary button reads `nextPageRoute` and uses Angular routing to point to `/portal`.

## Connected files

- `frontend/src/app/pages/landing/landing.component.html`
- `frontend/src/app/pages/landing/landing.component.scss`
- `frontend/src/app/app.routes.ts`
- `frontend/src/app/shared/theme-switcher/theme-switcher.component.ts`

## Business logic

The page communicates the approved Page 1 product story:

- Trainers can manage leads, groups, clients, targets, and progress tracking.
- Clients can view profile, goals, daily targets, weekly targets, monthly targets, and submit progress.

No authentication, backend, database, or dashboard behavior is implemented.

## Assumptions

The temporary app name is `CoachFlow Studio`. The Page 2 destination URL is `/portal`.

## Future improvements

After approval, Page 2 can be implemented at `/trainer-client-login` with Trainer Login, Trainer Signup, and Client Login.
