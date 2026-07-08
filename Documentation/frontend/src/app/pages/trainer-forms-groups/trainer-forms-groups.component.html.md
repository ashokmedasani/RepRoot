# frontend/src/app/pages/trainer-forms-groups/trainer-forms-groups.component.html

## What this file does

Renders the Forms & Groups dashboard and empty state.

## Why this file exists

The page needs a clear empty state before setup and clean dashboard sections after setup. The actual builders live on separate guided routes.

## Page or module

Trainer Forms & Groups page.

## Important sections

- No-form empty state with Create Form button.
- Public Lead Form card with request stats, public link, copy button, field summary, and edit form button.
- Form Requests table with Pending, Approved, Deleted, monthly filter, details, and client access actions.
- Groups section with compact group rows, client form status, View users link, and edit form link.
- Create Client Access panel.
- Load error panel shown when the API cannot return an overview.

## Business logic

The dashboard no longer embeds the form builder or approved user lists inside group cards. If no form exists, it directs trainers to `/trainer/forms/create`; group users open through `/trainer/groups/:groupId/users`.

## Connected files

- `trainer-forms-groups.component.ts`
- `trainer-forms-groups.component.scss`
