# frontend/src/app/pages/trainer-lead-form-create/trainer-lead-form-create.component.ts

## What this file does

Controls the guided public lead form creation page at `/trainer/forms/create`.

## Why this file exists

Form creation should happen outside the Forms & Groups dashboard so trainers can follow a focused setup flow.

## Important behavior

- Loads existing lead form data when editing.
- Shows universal core fields in the template.
- Saves custom fields through `FormsGroupsApiService`.
- Redirects new setup to group creation after saving.

## Connected files

- `trainer-lead-form-create.component.html`
- `trainer-lead-form-create.component.scss`
- `frontend/src/app/shared/form-field-builder/form-field-builder.component.ts`
