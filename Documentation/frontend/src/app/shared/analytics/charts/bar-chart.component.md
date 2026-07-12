# frontend/src/app/shared/analytics/charts/bar-chart.component.ts

## What changed

Bar and horizontal-bar rows now show exact values on hover and pin the selected value when clicked.

## Why it changed

Client template Overview charts need readable interactive values while preserving graph-engine chart type decisions.

## UI behavior

Hovering a bar shows label and value. Clicking a bar keeps that value visible below the chart.

## API or database impact

None.

## Testing

Verified with `npm run build`.
