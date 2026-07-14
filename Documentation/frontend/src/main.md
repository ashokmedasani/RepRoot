# src/main.ts

## What this file does

Bootstraps the standalone Angular application and registers the router.

## Why this file exists

This is the frontend runtime entry point used by Angular build tooling.

## Page or module

Global frontend application bootstrap.

## Important functions

- `import 'zone.js'`: loads Angular's default change detection runtime before bootstrapping.
- `provideHttpClient`: enables Angular services to call the Django REST API.
- `bootstrapApplication`: starts the Angular app with `AppComponent`.
- `provideRouter`: registers the route configuration.

## Data flow

The file does not process business data. It passes route configuration into Angular so pages can be displayed.

## Connected files

- `frontend/src/app/app.component.ts`
- `frontend/src/app/app.routes.ts`
- `frontend/src/app/core/api/trainer-auth-api.service.ts`

## Business logic

None.

## Assumptions

Standalone Angular components are preferred for the initial application structure. The app currently uses Angular's default Zone.js change detection runtime.

## Future improvements

Global HTTP and runtime error providers are registered. Future additions should preserve the centralized error and authentication behavior.

## 2026-07-13 global error handling

Registers the functional page-error HTTP interceptor and Angular global error handler. Validation and authentication errors keep their existing local behavior.
