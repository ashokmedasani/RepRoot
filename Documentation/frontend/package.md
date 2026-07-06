# frontend/package.json

## What this file does

Defines frontend package metadata, scripts, Angular dependencies, and app dependencies.

## Why this file exists

The Angular app needs a package manifest for installing dependencies and running development/build commands.

## Page or module

Frontend project configuration.

## Important scripts

- `npm run start`: starts Angular dev server.
- `npm run build`: creates production build.
- `npm run test`: runs Angular tests.

## Important dependencies

- Angular 20 packages.
- `rxjs`, `tslib`, and `zone.js`.
- `country-state-city`: provides global country and state/region data for Profile Setup and Profile pages.

## Business logic

No business logic lives here, but trainer profile country/state dropdowns depend on `country-state-city`.

## Connected files

- `frontend/src/app/pages/trainer-profile/trainer-profile.component.ts`
- `frontend/src/app/pages/trainer-profile-setup/trainer-profile-setup.component.ts`

## Future improvement notes

Audit and update dependencies before production deployment.
