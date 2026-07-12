# frontend/src/app/pages/trainer-group-users/trainer-group-users.component.html

## What this file does

Renders the group users page.

## Important sections

- Standard top navigation.
- Group title and back action.
- Active users table.
- Empty state when no users exist.

## Connected files

- `trainer-group-users.component.ts`
- `trainer-group-users.component.scss`

## Update

Tracking Templates tab renders trainer-level template cards (fields shown as optional previews) with Manage/Edit Template links to `/trainer/templates`.

## Update 2

Tracking Templates tab and section removed; tabs are Overview, Approved Users, Client Registration Form, and Settings.

## Update 3

Overview renders only summary cards and the five-person Recent Approved Users section. Approved Users and Client Registration Form now render only inside their own tabs.

## Update 4

Settings renders a single expandable card with Group Name, Group Description, and Save Group. Access rules are no longer displayed in this page.
