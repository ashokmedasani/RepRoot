# angular.json

## 2026-07-13 production audit

Production component-style budgets now match the current application scale while retaining a 24 kB hard failure threshold. Audited CommonJS transitive dependencies required by PDF/canvas export are explicitly declared so production builds still surface new, unexpected optimization fallbacks.

## What this file does

Configures the Angular application project, build target, serve target, assets, and global styles.

## Why this file exists

Angular CLI and Angular build tooling use this file to understand how to compile and serve the web application.

## Page or module

Project-level frontend configuration.

## Important configuration

- Application name: `trainer-management-platform`.
- Source root: `src`.
- Browser entry point: `frontend/src/main.ts`.
- Global styles: `frontend/src/styles.scss`.

## Data flow

No business data flows through this file.

## Connected files

- `frontend/package.json`
- `frontend/src/main.ts`
- `frontend/src/styles.scss`
- `frontend/tsconfig.app.json`

## Business logic

None.

## Assumptions

The frontend app is the only Angular project in the workspace for this stage.

## Future improvements

Add test and lint architect targets when those workflows are introduced.
