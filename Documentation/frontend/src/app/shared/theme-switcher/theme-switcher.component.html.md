# src/app/shared/theme-switcher/theme-switcher.component.html

## What this file does

Renders the theme selector buttons.

## Why this file exists

The UI needs a simple, accessible way to preview and switch available themes.

## Page or module

Shared UI theme module.

## Important elements

- Theme buttons with `aria-pressed`.
- Swatches that visually distinguish each theme.
- Button titles that describe each theme.

## Data flow

The template loops over theme options from the component and sends selected theme IDs back through click events.

## Connected files

- `frontend/src/app/shared/theme-switcher/theme-switcher.component.ts`
- `frontend/src/app/shared/theme-switcher/theme-switcher.component.scss`

## Business logic

None.

## Assumptions

Four initial themes are enough for Page 1 review while keeping the system extendable.

## Future improvements

Add keyboard shortcut support only if accessibility review asks for it.
