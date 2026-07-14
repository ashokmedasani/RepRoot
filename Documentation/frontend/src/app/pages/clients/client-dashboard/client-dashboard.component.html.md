# frontend/src/app/pages/clients/client-dashboard/client-dashboard.component.html

## 2026-07-13 responsibilities

Implements the authenticated client dashboard with five KPIs, a fixed-height upcoming-schedule list, 24-hour urgency treatment, and assigned-template analytics grouped by template with empty graphs omitted.

## Integration

This file participates in the targeted workflow refinements documented in `Documentation/CHANGELOG-refinements-2026-07-13.md`. Existing theme tokens and business rules remain authoritative.

## Verification

Covered by the successful Angular production build and relevant backend API regression tests.

## 2026-07-13 overdue schedule organization

The Schedules section displays a compact overdue badge and separate Overdue Schedules and Upcoming Schedules groups without adding a sixth main KPI.

## 2026-07-13 visual consistency pass

Aligned this file with the shared Dashboard-style page header, portal navigation, action controls, and unclipped profile-image treatment. Verified at port 4400 with no horizontal overflow and covered by the production Angular build.
