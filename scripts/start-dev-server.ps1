param(
  [int]$Port = 4300
)

$workspace = Split-Path -Parent $PSScriptRoot
$frontend = Join-Path $workspace "frontend"
$logDirectory = Join-Path $workspace ".dev-server"

if (-not (Test-Path -LiteralPath $logDirectory)) {
  New-Item -ItemType Directory -Path $logDirectory | Out-Null
}

$stdout = Join-Path $logDirectory "stdout.log"
$stderr = Join-Path $logDirectory "stderr.log"

Start-Process `
  -FilePath "npm.cmd" `
  -ArgumentList @("run", "start", "--", "--host", "127.0.0.1", "--port", "$Port") `
  -WorkingDirectory $frontend `
  -WindowStyle Hidden `
  -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr
