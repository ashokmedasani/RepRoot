# backend/config/wsgi.py

## What this file does

Exposes the Django WSGI application.

## Why this file exists

WSGI is the standard interface for many Django deployment environments.

## Page or module

Backend project configuration.

## Important functions/classes/components

- `get_wsgi_application`: creates the WSGI callable.

## Data flow

Server requests flow through the WSGI callable into Django.

## Connected files

- `backend/config/settings.py`

## Business logic

None.

## Assumptions

The backend should remain compatible with common Django hosting options.

## Future improvement notes

Deployment-specific changes can be added when hosting is selected.
