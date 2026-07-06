# src/app/shared/theme-switcher/theme-switcher.component.scss

## What this file does

Styles the theme switcher control, including active state, hover state, focus state, and theme swatches.

## Why this file exists

The theme selector must feel consistent with the premium SaaS visual direction and remain usable on smaller screens.

## Page or module

Shared UI theme module.

## Important styles

- Flexible wrapping button group.
- Active selected theme styling.
- Circular swatches for each approved theme, including Black and Gold.

## Data flow

No business data flows through this stylesheet. It consumes CSS variables from `frontend/src/styles.scss`.

## Connected files

- `frontend/src/styles.scss`
- `frontend/src/app/shared/theme-switcher/theme-switcher.component.html`

## Business logic

None.

## Assumptions

Swatches are decorative helpers and do not replace the text labels.

## Future improvements

Extract shared button tokens when more controls are introduced.
