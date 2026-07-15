# frontend/src/app/pages/trainer/trainer-dashboard/trainer-dashboard.component.ts

## 2026-07-15 UI, workflow, and bug fixes

KPI cards show only the actual value (no '/ limit' text). Activity order is now: Pending Requests (always visible), Client Tracking Center (schedule overview + upcoming schedules), then the Recent Activity accordion (recent clients and templates).

## 2026-07-13 chart-based tracking center

Builds shared `ChartSpec` objects for time-priority bars and exclusive pending/completed schedule status. This reuses the chart renderer without duplicating Chart.js setup or schedule calculations.

## 2026-07-13 Client Action Center follow-up

Loads pending client profile edits with schedules and controls the Schedules/Profile Edits views inside one Client Activity Queue dropdown.

## 2026-07-13 responsibilities

Implements the compact five-value Schedule Overview, emphasizes schedules due within 24 hours, sorts upcoming schedules chronologically, and uses the shared fixed-height list and confirmation system.

## Integration

This file participates in the targeted workflow refinements documented in `Documentation/CHANGELOG-refinements-2026-07-13.md`. Existing theme tokens and business rules remain authoritative.

## Verification

Covered by the successful Angular production build and relevant backend API regression tests.

## 2026-07-13 overdue schedule organization

Separates overdue schedules from future due windows, maintains grouped chronological queue state, and updates every affected KPI immediately when a schedule is marked complete.
