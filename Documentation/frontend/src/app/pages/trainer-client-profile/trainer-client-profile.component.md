# frontend/src/app/pages/trainer/trainer-client-profile/trainer-client-profile.component.ts

## What changed

The trainer client profile now has one unified Client Information section with view mode and edit mode. Normal client fields and registration-form answers can be edited by the trainer; read-only values such as Form Submission Reference ID and joined date stay protected.

## Why it changed

The prior profile editing workflow lived mostly in an Account & Access dialog and did not provide a clear way to edit the client profile properly.

## Files affected

- `trainer-client-profile.component.ts`
- `trainer-client-profile.component.html`
- `trainer-client-profile.component.scss`
- `frontend/src/app/core/api/forms-groups-api.service.ts`
- `backend/accounts/views.py`

## UI behavior

`Edit Client Information` opens inline fields for first name, last name, email, username, status, and custom registration answers. `Save Client Information` persists changes; `Cancel` returns to view mode. Password reset remains available separately.

## API impact

Uses `PUT /api/accounts/trainer/forms-groups/clients/<client_id>/` through `updateClientProfile`. No database schema change.

## Testing

Verified with `npm run build`.
