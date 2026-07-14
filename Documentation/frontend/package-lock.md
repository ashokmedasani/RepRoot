# frontend/package-lock.json

## What this file does

Locks exact installed frontend dependency versions.

## Why this file exists

The lockfile keeps installs reproducible across development machines and deployment builds.

## Page or module

Frontend dependency management.

## Important changes

- Includes `country-state-city` for global country and state/region dropdown data.

## Business logic

No direct business logic lives here.

## Connected files

- `frontend/package.json`

## Future improvement notes

Regenerate only through `npm install` when dependencies intentionally change.

## 2026-07-13 production audit

Lock data reflects removal of `xlsx` and installation of `write-excel-file@4.1.1`; the resulting dependency tree audits cleanly.

The final lock refresh aligns Angular framework packages at 20.3.26 and resolves the nested Babel advisory. `npm audit` reports zero known vulnerabilities.
