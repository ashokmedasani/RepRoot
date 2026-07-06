# src/app/pages/landing/landing.component.html

## What this file does

Renders the Page 1 landing page layout and content.

## Why this file exists

The user needs a polished project introduction page that explains the platform and offers a single clear starting action.

## Page or module

Landing / Project Introduction Page.

## Important sections

- Top navigation with temporary brand and theme switcher.
- Hero section introducing the trainer-client management platform.
- Primary `Let's Start` button.
- Platform overview metric cards.
- Trainer capability cards.
- Client capability cards.

## Data flow

The template reads static content from `LandingComponent`. The primary action uses `routerLink` to point to `/portal`.

## Connected files

- `frontend/src/app/pages/landing/landing.component.ts`
- `frontend/src/app/pages/landing/landing.component.scss`
- `frontend/src/app/shared/theme-switcher/theme-switcher.component.html`

## Business logic

The template only presents approved Page 1 information. It does not perform authentication, API calls, or database operations.

## Assumptions

The metric card values are illustrative landing-page presentation content, not real data from a backend.

## Future improvements

Replace illustrative metrics with live platform data only after backend and dashboard modules are approved.
