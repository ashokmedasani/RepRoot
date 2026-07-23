# frontend/src/app/pages/trainer/trainer-dashboard/trainer-dashboard.component.ts

## What this file does

Trainer dashboard at `/trainer/dashboard`: top KPI tiles, compact schedule KPI, collapsible upcoming schedules, and collapsible activity lists.

## Why this file exists

The sidebar's Dashboard item was previously a dead placeholder; this gives trainers a real landing overview.

## Connected files

- `frontend/src/app/core/api/forms-groups-api.service.ts` (`getOverview`)
- `frontend/src/app/core/api/templates-api.service.ts`

## Update

- Preserved existing group/client/request/template KPI logic.
- Added schedule summary state from `getUpcomingReminders`.
- Added accordion state for Activity and Upcoming Schedules.
- Testing performed: `npm run build`.
