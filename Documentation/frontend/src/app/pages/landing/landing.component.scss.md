# src/app/pages/landing/landing.component.scss

## What this file does

Styles the Page 1 landing page, including hero layout, navigation, cards, responsive behavior, and call-to-action styling.

## Why this file exists

The landing page must look production-ready, premium, modern, minimal, responsive, and accessible.

## Page or module

Landing / Project Introduction Page.

## Important styles

- Responsive shell with constrained content width.
- Premium SaaS hero typography.
- Theme-aware cards and metric panels.
- Responsive one-column layouts for tablet and mobile screens.
- Accessible focus and hover states for the primary action.

## Data flow

No business data flows through this stylesheet. It consumes theme variables from `frontend/src/styles.scss`.

## Connected files

- `frontend/src/styles.scss`
- `frontend/src/app/pages/landing/landing.component.html`

## Business logic

None.

## Assumptions

The landing page should be self-contained until a global public layout is approved.

## Future improvements

Extract repeated card and button styles into shared UI components after more pages are approved.
