# frontend/src/app/core/api/forms-groups-api.service.ts

## 2026-07-15 UI, workflow, and bug fixes

resetClientPassword accepts an optional trainer-defined temporary password (Option A consistency with manual creation).

## 2026-07-13 Client Action Center follow-up

Adds the typed `ClientProfileEditActivity` contract and extends the existing upcoming-reminders response type with profile-edit activities and their KPI count.

## 2026-07-13 targeted refinement

Adds manual client, public group registration, group-submission, reference ID, credential, and compact schedule-summary API contracts.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Provides typed Angular HTTP methods for the Forms & Groups setup flow and public lead form flow.

## Why this file exists

The trainer Forms & Groups page and public applicant page need a focused API client separate from trainer authentication/profile calls.

## Page or module

Angular core API services.

## Important functions/classes/components

- `getOverview`: loads Form 1, groups, pending forms, approved forms, and maximum group count.
- `saveLeadForm`: creates or edits the trainer public lead form.
- `createGroup`: creates a trainer group.
- `saveRegistrationForm`: creates or edits a group's client registration form.
- `getGroupUsers`: loads active users created under one group.
- `deletePendingForm`: deletes a pending applicant request.
- `createClientAccess`: converts a pending applicant into client access.
- `updateClientProfile`: lets the trainer save editable client profile and registration-answer fields while keeping protected values such as reference ID outside the payload.
- `getUpcomingReminders`: returns upcoming schedule rows plus summary counts for total pending and due-within ranges.
- `getPublicForm` and `submitPublicForm`: support unauthenticated applicants.
- Dynamic field types include location and address in addition to text, phone, choice, number, and date types.

## Data flow

Protected trainer methods include the stored trainer auth token. Public form methods call unauthenticated backend routes. The dashboard uses one overview payload while guided setup pages reuse the create/update endpoints.

## Update

Schedule summary typing and trainer-side client profile update typing were added for dashboard and client-profile refinements. No database impact from this frontend service change.

## Testing

Verified by `npm run build`.

## 2026-07-13 overdue schedule organization

`ScheduleSummary` includes the backend-provided `overdue` count used by the Client Action Center and organized schedule queue.

## Connected files

- `frontend/src/app/pages/trainer-forms-groups/trainer-forms-groups.component.ts`
- `frontend/src/app/pages/public-lead-form/public-lead-form.component.ts`
- `backend/accounts/views.py`
