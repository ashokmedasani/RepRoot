# src/app/shared/theme-switcher/theme-switcher.component.ts

## What this file does

Defines a reusable standalone component for selecting the active application theme.

## Why this file exists

Page 1 needs visible theme support, and future pages should reuse the same theme switching logic rather than duplicating it.

## Page or module

Shared UI theme module.

## Important classes

- `ThemeSwitcherComponent`: reads available themes and sends user selections to `ThemeService`.
- Uses Angular's `inject()` helper to access `ThemeService` before initializing readonly view properties.

## Data flow

Theme options come from `ThemeService.themes`. User clicks call `selectTheme`, which passes the selected ID back to `ThemeService`.

## Connected files

- `frontend/src/app/shared/theme-switcher/theme-switcher.component.html`
- `frontend/src/app/shared/theme-switcher/theme-switcher.component.scss`
- `frontend/src/app/core/theme/theme.service.ts`
- `frontend/src/app/pages/landing/landing.component.ts`

## Business logic

None. This is presentation and theme preference behavior only.

## Assumptions

The theme switcher is safe to show publicly on Page 1 because theme selection is not user-account-specific yet.

## Future improvements

Move the switcher into a global navigation component when the application shell is approved.
