# frontend/src/app/pages/trainer/trainer-client-profile/trainer-client-profile.component.scss

## What changed

Added styles for the unified Client Information view/edit panel, including detail tiles, edit-grid controls, and compact action rows.

## Why it changed

The trainer needs a large but organized section for editing client information without spreading fields across multiple cards.

## UI behavior

Desktop shows three-column detail/edit grids. Mobile stacks the client information fields with no horizontal overflow.

## API or database impact

Style-only file; no API or database impact.

## Testing

Verified with `npm run build`.
