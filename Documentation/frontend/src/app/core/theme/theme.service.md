# src/app/core/theme/theme.service.ts

## What this file does

Manages the active UI theme, persists it in browser storage, and applies it to the document root.

## Why this file exists

The application requires scalable theme support that can affect every page and UI component.

## Page or module

Core theme module.

## Important functions and properties

- `themes`: approved list of available themes.
- `activeTheme`: Angular signal containing the current theme ID.
- `initializeTheme`: loads the saved theme or falls back to the main theme.
- `setTheme`: updates state, applies the theme, and persists the preference.

## Data flow

The user selects a theme in `ThemeSwitcherComponent`. The selected `ThemeId` flows into `ThemeService.setTheme`, which updates `activeTheme`, writes to `localStorage`, and sets `data-theme` on the root HTML element.

## Connected files

- `frontend/src/app/core/theme/theme.model.ts`
- `frontend/src/app/shared/theme-switcher/theme-switcher.component.ts`
- `frontend/src/styles.scss`
- `frontend/src/app/app.component.ts`

## Business logic

No trainer or client business rules exist here. This file implements the confirmed theme behavior, including the Black and Gold theme.

## Assumptions

The browser is the only current runtime, but platform checks are included so the service remains safe for future server-side rendering.

## Future improvements

Allow user profile theme preferences to sync from the backend after authentication is approved.
