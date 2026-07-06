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

Add global providers for HTTP, animations, and app configuration when backend-connected pages are approved.
