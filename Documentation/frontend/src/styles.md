# frontend/src/styles.scss

## What this file does

Defines global styles, theme variables, shared base element styling, shared photo upload card styles, top trainer navigation styles, and profile-header primitives.

## Why this file exists

The app needs consistent theme colors, typography, form foundations, and reusable UI patterns across standalone Angular pages.

## Page or module

Global frontend styling.

## Important styles

- Theme variables for Main, Dark, Green Wellness, Purple Premium, and Black Gold themes.
- Base layout and form element defaults.
- Shared `.photo-manager`, `.photo-field`, `.photo-frame`, `.photo-placeholder`, `.photo-copy`, `.secondary-action`, and `.visually-hidden` styles used by Profile Setup and Profile pages.
- Shared `.top-shell` navigation styles.
- Shared `.profile-hero`, `.cover-band`, `.hero-content`, `.hero-photo`, and `.hero-copy` profile-header styles.

## Business logic

No business logic lives here. Shared photo and profile-header styles support the existing-photo/change-photo UI and the top trainer navigation.

## Connected files

- `frontend/src/app/pages/trainer-profile/trainer-profile.component.html`
- `frontend/src/app/pages/trainer-profile-setup/trainer-profile-setup.component.html`

## Future improvement notes

Move shared UI primitives into a component library or design-system layer as the app grows.

## 2026-07-13 visual consistency pass

Aligned this file with the shared Dashboard-style page header, portal navigation, action controls, and unclipped profile-image treatment. Verified at port 4400 with no horizontal overflow and covered by the production Angular build.
