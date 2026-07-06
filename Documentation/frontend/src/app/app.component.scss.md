# src/app/app.component.scss

## What this file does

Sets the root component to fill the viewport and inherit the active theme background.

## Why this file exists

The application shell needs stable full-page layout behavior for routed pages.

## Page or module

Global frontend application shell.

## Important styles

- `:host` uses `display: block`.
- Minimum height is set to `100vh`.
- Background uses `--app-bg`.

## Data flow

No business data flows through this stylesheet. Theme data is provided through CSS variables.

## Connected files

- `frontend/src/styles.scss`
- `frontend/src/app/app.component.ts`

## Business logic

None.

## Assumptions

Each page controls its own internal layout while the shell provides the background canvas.

## Future improvements

Add shell-level layout styles only when global navigation is approved.
