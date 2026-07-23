# frontend/src/app/shared/analytics/charts/pie-chart.component.ts

## 2026-07-13 hover and click values

The normal doughnut view contains no in-segment values. Hovering a segment opens a blue floating label with category, exact value, and percentage; clicking pins the label until it is clicked again or the page scrolls.

## 2026-07-13 reliable hover value repair

Adds a stable accessible HTML hover-value overlay driven by the nearest doughnut segment. It displays category, value, and percentage while hovering, then clears on leave or scroll without resizing the canvas.

## 2026-07-13 hover treatment follow-up

The doughnut panel gains theme-border emphasis and stronger shadow without moving the canvas. Individual slices retain hover offset and value/percentage tooltips.

## 2026-07-13 hospital-analytics visual alignment

Uses a full 330px doughnut panel with optional subtitle, bottom legend, theme palette, and value/percentage hover tooltips. Empty data remains suppressed or explicitly described.

## What changed

Pie slices show category, count, and percentage in a floating hover label, and clicking a slice pins that value.

## Why it changed

Client template Overview pie charts need clear category-level values without hardcoding field graph types.

## UI behavior

Hovering a slice shows category, count, and percentage beside the pointer. Clicking a slice pins that floating label until the same slice is clicked again or the page scrolls.

## API or database impact

None.

## Testing

Verified with `npm run build`.
