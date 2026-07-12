# frontend/src/app/shared/analytics/charts/pie-chart.component.ts

## What changed

Pie slices now show category, count, and percentage on hover, and clicking a slice pins that value below the chart.

## Why it changed

Client template Overview pie charts need clear category-level values without hardcoding field graph types.

## UI behavior

Hovering a slice shows the category/count/percentage tooltip. Clicking a slice keeps the same information visible.

## API or database impact

None.

## Testing

Verified with `npm run build`.
