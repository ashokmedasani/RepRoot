# frontend/src/app/pages/trainer/trainer-templates/trainer-templates.component.ts

## What this file does

Dedicated Templates section: shows the trainer's template slots (max five), the three standard templates to adopt, and the trainer's own templates with edit/delete actions.

## Why this file exists

Templates are trainer-level and shared across all groups, so they are managed in one place instead of inside each group.

## Page or module

Trainer Templates page at `/trainer/templates`.

## Important functions/classes/components

- `adoptStandard`: one-click copy of a standard template (blocked when adopted or slots are full).
- `deleteTemplate`: confirms, deletes, and reminds that client entries are kept.
- `slotsUsed` / `hasFreeSlot` against `max_templates` from the API.

## Data flow

Loads `getTemplates()` and `getStandardTemplates()` on init and after every change.

## Connected files

- `frontend/src/app/core/api/templates-api.service.ts`
- `frontend/src/app/pages/trainer/trainer-tracking-template-create/trainer-tracking-template-create.component.ts`
