# frontend/src/app/shared/trainer-page-shell/trainer-page-shell.component.ts

## 2026-07-13 storage gauge behavior

Formats used/quota bytes, clamps the percentage to the gauge range, and consumes the session-stable response. Failure leaves navigation usable and shows an unavailable state.

## 2026-07-13 targeted refinement

Preserves the trainer portal shell while supporting the refined navigation and account workflow presentation.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

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

## Update: sidebar layout

The shell is now a fixed left sidebar (brand, icon nav with Dashboard/Forms & Groups/Templates/Clients/References/Profile/Settings, Sign Out pinned at the bottom) matching the FitCoach reference design; it collapses to a horizontal bar under 900px. The footer was removed.

## 2026-07-13 trainer data usage

Loads the authenticated trainer-wide usage total for every shared trainer page and formats bytes into B, KB, MB, GB, or TB.
