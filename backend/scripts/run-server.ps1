$ErrorActionPreference = "Stop"

$backendRoot = Split-Path -Parent $PSScriptRoot
$python = Join-Path $backendRoot ".venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $python)) {
  Write-Error "Backend virtual environment not found. Run: python -m venv .venv"
}

& $python manage.py runserver 127.0.0.1:8000
