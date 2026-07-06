# scripts/start-dev-server.ps1

## What this file does

Starts the Angular development server from the `frontend/` folder in a hidden background process and writes stdout and stderr logs to `.dev-server/`.

## Why this file exists

The desktop tool needs a reliable way to launch the local Angular app for visual verification without keeping an interactive terminal session open. The Angular app now lives in `frontend/`.

## Page or module

Local development tooling for the frontend application.

## Important parameters

- `Port`: defaults to `4200`.

## Data flow

No product data flows through this script. It starts `npm run start` and writes process logs to local files.

## Connected files

- `frontend/package.json`
- `frontend/angular.json`

## Business logic

None.

## Assumptions

The script assumes npm is available as `npm.cmd` on Windows.

## Future improvements

Add optional process cleanup once a broader local developer workflow is approved.
