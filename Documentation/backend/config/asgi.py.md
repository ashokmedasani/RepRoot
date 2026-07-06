# backend/config/asgi.py

## What this file does

Exposes the Django ASGI application.

## Why this file exists

ASGI is needed for async-capable Django deployments and some server environments.

## Page or module

Backend project configuration.

## Important functions/classes/components

- `get_asgi_application`: creates the ASGI callable.

## Data flow

Server requests flow through the ASGI callable into Django.

## Connected files

- `backend/config/settings.py`

## Business logic

None.

## Assumptions

ASGI is included now so deployment options remain flexible later.

## Future improvement notes

Add websocket or async routing only if a future approved feature requires it.
