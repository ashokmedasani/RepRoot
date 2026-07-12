# frontend/src/app/shared/analytics/charts/line-chart.component.ts

## What changed

Line chart points now expose hover tooltips with label/date and value, and clicking a point pins the selected value below the chart.

## Why it changed

Client template Overview graphs need interactive values without changing the existing graph-engine chart selection logic.

## UI behavior

Hovering a point shows the browser tooltip. Clicking a point displays the same value in a compact chart tooltip row.

## API or database impact

None.

## Testing

Verified with `npm run build`.
