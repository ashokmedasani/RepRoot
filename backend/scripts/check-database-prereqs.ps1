$ErrorActionPreference = "Continue"

Write-Host "Checking local database prerequisites..."

$docker = Get-Command docker -ErrorAction SilentlyContinue
$psql = Get-Command psql -ErrorAction SilentlyContinue
$postgres = Get-Command postgres -ErrorAction SilentlyContinue

if ($docker) {
  Write-Host "Docker found: $($docker.Source)"
  Write-Host "Recommended start command from project root: docker compose up -d postgres"
} else {
  Write-Host "Docker not found."
}

if ($psql) {
  Write-Host "psql found: $($psql.Source)"
} else {
  Write-Host "psql not found."
}

if ($postgres) {
  Write-Host "postgres server binary found: $($postgres.Source)"
} else {
  Write-Host "postgres server binary not found."
}

if (-not $docker -and -not $postgres) {
  Write-Host "No runnable PostgreSQL setup was found. Install Docker Desktop or PostgreSQL, then run migrations."
}
