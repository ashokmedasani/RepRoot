# backend/accounts/migrations/0009_remove_trackingtemplate_references_and_more.py

## What this file does

Moves reference sharing from templates to assignments: removes the `references` many-to-many from `TrackingTemplate` and adds it to `TemplateAssignment`.

## Why this file exists

Product decision: references are chosen per client when a template is assigned, not baked into the template itself.

## Connected files

- `backend/accounts/models.py`
