# frontend/src/app/shared/analytics/charts/line-chart.component.ts

## 2026-07-13 hover and click values

Values remain hidden during the normal chart view. Hovering a point opens a blue floating label with its contextual date/time and value; clicking pins the label until it is clicked again or the page scrolls.

## 2026-07-13 reliable hover value repair

Adds a stable accessible HTML hover-value overlay driven by Chart.js nearest-point detection. Moving across the plot shows date/time, value, and unit; leaving or scrolling hides it. The overlay remains mounted so responsive Chart.js resizing is not triggered during hover.

## 2026-07-13 hover treatment follow-up

The chart panel strengthens its theme border and shadow on hover without moving the canvas, keeping pointer coordinates stable. Existing Chart.js point hover tooltips continue to show date/time and values.

## 2026-07-13 hospital-analytics visual alignment

Uses a 330px analytical panel, stronger heading/subtitle, three-pixel smoothed trend line, visible hover points, and theme-aware grid/tooltips. It remains driven by the reusable `ChartSpec` engine.

## 2026-07-13 targeted refinement

Uses graph-engine tooltip metadata to display submission date/time and category context alongside values.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What changed

Line chart points expose floating hover tooltips with label/date and value, and clicking a point pins the selected value.

## Why it changed

Client template Overview graphs need interactive values without changing the existing graph-engine chart selection logic.

## UI behavior

Hovering a point shows its contextual value beside the pointer. Clicking a point pins that floating label until the same point is clicked again or the page scrolls.

## API or database impact

None.

## Testing

Verified with `npm run build`.
