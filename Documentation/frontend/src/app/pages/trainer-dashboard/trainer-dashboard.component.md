# frontend/src/app/pages/trainer/trainer-dashboard/trainer-dashboard.component.ts

## What this file does

Trainer dashboard at `/trainer/dashboard`: stat tiles (groups, approved clients, pending requests, templates in use) plus pending-request, recent-client, and template quick lists.

## Why this file exists

The sidebar's Dashboard item was previously a dead placeholder; this gives trainers a real landing overview.

## Connected files

- `frontend/src/app/core/api/forms-groups-api.service.ts` (`getOverview`)
- `frontend/src/app/core/api/templates-api.service.ts`
