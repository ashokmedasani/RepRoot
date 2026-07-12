# frontend/src/app/pages/trainer/trainer-client-profile/trainer-client-profile.component.html

## What changed

The top profile area now renders a unified Client Information panel instead of splitting key details into unrelated cards/dialog content.

## Why it changed

Trainers need to view and edit client details in one predictable place.

## UI behavior

View mode shows core client identity, group/status, joined date, reference ID, and registration answers. Edit mode shows inline controls plus Save and Cancel actions. Reference ID remains disabled/read-only.

## API impact

Submits editable values through the existing component service layer; no direct API logic lives in the template.

## Testing

Verified with `npm run build`.
