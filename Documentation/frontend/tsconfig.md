# tsconfig.json

## What this file does

Defines the shared TypeScript and Angular compiler settings for the frontend application.

## Why this file exists

Strict compiler settings help keep the Angular codebase maintainable as the platform grows.

## Page or module

Project-level TypeScript configuration.

## Important settings

- `strict` TypeScript mode is enabled.
- Angular strict template checks are enabled.
- Modern browser-targeted TypeScript output is configured.

## Data flow

No business data flows through this file.

## Connected files

- `frontend/tsconfig.app.json`
- Angular compiler tooling

## Business logic

None.

## Assumptions

The project should start with strict typing rather than loosen rules later.

## Future improvements

Add path aliases when the codebase grows enough to benefit from them.
