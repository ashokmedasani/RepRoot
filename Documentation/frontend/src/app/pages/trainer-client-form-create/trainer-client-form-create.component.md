# frontend/src/app/pages/trainer-client-form-create/trainer-client-form-create.component.ts

## What this file does

Controls the guided client creation form page at `/trainer/groups/:groupId/client-form/create`.

## Why this file exists

Each trainer group needs a client creation form before pending leads can be converted into client access for that group.

## Important behavior

- Loads the selected group from Forms & Groups overview data.
- Loads existing client form custom fields when editing.
- Saves the group client registration form.
- Redirects back to the Forms & Groups dashboard after saving.

## Connected files

- `trainer-client-form-create.component.html`
- `trainer-client-form-create.component.scss`
- `frontend/src/app/shared/form-field-builder/form-field-builder.component.ts`
