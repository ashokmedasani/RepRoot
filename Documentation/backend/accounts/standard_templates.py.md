# backend/accounts/standard_templates.py

## What this file does

Defines the three standard tracking templates (Nutrition Details, Vitamins & Supplements, Daily Progress Check-in) every trainer can adopt with one click.

## Why this file exists

Trainers are limited to five templates. Shipping ready-made templates saves setup time; adopting one copies it into the trainer's own template list where it can be renamed or customized.

## Page or module

Backend accounts module, tracking templates feature.

## Important functions/classes/components

- `STANDARD_TEMPLATES`: list of template definitions with key, name, purpose, cadence, accent, and fields.
- `get_standard_template(key)`: returns one definition or `None`.
- Template fields never carry a `required` flag - nothing in a template is mandatory for clients.

## Data flow

`StandardTemplateListView` returns the list (flagging which keys the trainer already adopted). `StandardTemplateAdoptView` copies one definition into a trainer-owned `TrackingTemplate` row, which counts toward the five-template limit.

## Connected files

- `backend/accounts/views.py`
- `backend/accounts/models.py`
