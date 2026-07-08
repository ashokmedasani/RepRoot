# frontend/src/app/shared/trainer-page-shell/trainer-page-shell.component.ts

## What this file does

Layout wrapper for trainer workspace pages: top navigation, page header with actions slot, and sign-out.

## Why this file exists

Keeps navigation and page chrome consistent across every trainer page.

## Page or module

Shared frontend components.

## Important functions/classes/components

- `TrainerSection` union now includes `templates` for the dedicated Templates section.
- Inputs: `title`, `eyebrow`, `subtitle`, `activeSection`, `maxWidth`, `titleId`.
- `signOut` clears trainer storage keys and redirects home.

## Connected files

- All `pages/trainer/*` components.
