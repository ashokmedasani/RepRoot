#!/bin/bash
set -euo pipefail

source /var/app/venv/*/bin/activate
python manage.py migrate --noinput
python manage.py enforce_legal_version
python manage.py collectstatic --noinput
