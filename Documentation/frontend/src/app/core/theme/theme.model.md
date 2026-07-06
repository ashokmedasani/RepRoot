# src/app/core/theme/theme.model.ts

## What this file does

Defines TypeScript types for the application theme system.

## Why this file exists

Theme IDs and labels need a shared type contract so components and services stay consistent.

## Page or module

Core theme module.

## Important types

- `ThemeId`: allowed theme identifiers.
- `ThemeOption`: display metadata for a selectable theme.

## Data flow

Theme IDs flow from the theme switcher into `ThemeService`, then into the document root as a `data-theme` value. `black-gold` is included as the Black and Gold theme option.

## Connected files

- `frontend/src/app/core/theme/theme.service.ts`
- `frontend/src/app/shared/theme-switcher/theme-switcher.component.ts`

## Business logic

None. This file supports the confirmed extendable theme requirement.

## Assumptions

Theme IDs should be explicit strings so unsupported themes cannot be selected accidentally.

## Future improvements

Add theme grouping or accessibility metadata if the theme list grows.
