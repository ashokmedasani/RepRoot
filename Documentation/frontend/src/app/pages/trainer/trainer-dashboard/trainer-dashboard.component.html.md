# frontend/src/app/pages/trainer/trainer-dashboard/trainer-dashboard.component.html

## 2026-07-13 attention KPI row follow-up

Keeps the priority and status graphs together in a two-column analytical row. Overdue, due-within-24-hours, profile edits, and recent completions now appear as a separate four-card KPI row before the Client Activity Queue.

## 2026-07-13 Client Tracking Center redesign

Replaces the dense KPI strip with two chart panels and an immediate-action summary. Overdue, due-within-24-hours, and profile-edit counts remain visible, with the fixed-height Client Activity Queue below.

## 2026-07-13 Client Action Center follow-up

Renames Schedule Overview to Client Action Center, adds the Profile Edits Awaiting Review KPI, and combines schedules and profile-edit reviews in one switchable Client Activity Queue. Edit rows link directly to the affected client page.

## 2026-07-13 responsibilities

Implements the compact five-value Schedule Overview, emphasizes schedules due within 24 hours, sorts upcoming schedules chronologically, and uses the shared fixed-height list and confirmation system.

## Integration

This file participates in the targeted workflow refinements documented in `Documentation/CHANGELOG-refinements-2026-07-13.md`. Existing theme tokens and business rules remain authoritative.

## Verification

Covered by the successful Angular production build and relevant backend API regression tests.

## 2026-07-13 final layout pass

Matches the Trainer Profile page header structure. Immediate, upcoming, and client-update work are three primary attention cards; pending/completed totals are a compact secondary strip instead of six equal KPI cards.

## 2026-07-13 overdue schedule organization

Adds a distinct red Past Due metric and separates queue rows under Overdue Schedules and Upcoming Schedules headings. The compact totals strip remains unchanged.
