# frontend/src/app/shared/analytics/charts/bar-chart.component.ts

## 2026-07-13 hover and click values

Values remain hidden during the normal chart view. Hovering a bar opens a blue floating value label beside the pointer; clicking pins that label until it is clicked again or the page scrolls.

## 2026-07-13 reliable hover value repair

Adds a stable accessible HTML hover-value overlay driven by Chart.js nearest-bar detection. Label, value, and unit display while the pointer is over the plot and clear on leave or scroll without adding/removing DOM around the responsive canvas.

## 2026-07-13 hover treatment follow-up

The chart panel gains theme-border emphasis and stronger shadow without moving the canvas. Individual bars retain palette-specific hover colors and Chart.js value tooltips.

## 2026-07-13 hospital-analytics visual alignment

Uses the shared palette across categories, 330px panels, optional subtitles, rounded bars, zero-based axes, and tooltip context. Vertical and horizontal modes still share one renderer.

## What changed

Bar and horizontal-bar rows show exact values in a floating interaction label and pin the selected value when clicked.

## Why it changed

Client template Overview charts need readable interactive values while preserving graph-engine chart type decisions.

## UI behavior

Hovering a bar shows its label and value beside the pointer. Clicking a bar pins that floating value until the same bar is clicked again or the page scrolls.

## API or database impact

None.

## Testing

Verified with `npm run build`.
