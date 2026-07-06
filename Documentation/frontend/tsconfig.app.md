# tsconfig.app.json

## What this file does

Extends the base TypeScript configuration for the Angular browser application.

## Why this file exists

Angular uses this file to know which application entry files should be compiled for the app build.

## Page or module

Frontend application build configuration.

## Important settings

- Entry file: `frontend/src/main.ts`.
- Includes Angular declaration files under `src`.

## Data flow

No business data flows through this file.

## Connected files

- `frontend/tsconfig.json`
- `frontend/src/main.ts`
- `frontend/angular.json`

## Business logic

None.

## Assumptions

No test-specific TypeScript configuration is needed until test files are added.

## Future improvements

Create a separate `tsconfig.spec.json` when frontend tests are introduced.
