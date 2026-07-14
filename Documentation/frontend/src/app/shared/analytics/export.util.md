# frontend/src/app/shared/analytics/export.util.ts

## 2026-07-13 production audit

Excel analytics exports use `write-excel-file` in browser mode. The export remains reusable and asynchronous while removing the vulnerable `xlsx` dependency.
