# Starts the Angular web frontend and Django backend for access over Wi-Fi.
# Usage: powershell -ExecutionPolicy Bypass -File .\scripts\start-web-test.ps1
#
# It opens two windows (backend + web frontend) and prints the URL to open.
# The phone and PC must be connected to the same Wi-Fi network.

$workspace = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $workspace "backend"
$frontend = Join-Path $workspace "frontend"

# Find this PC's LAN IPv4 address (prefer a 192.168.x.x Wi-Fi address).
$candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Select-Object -ExpandProperty IPAddress

$lanIp = $candidates | Where-Object { $_ -like '192.168.*' } | Select-Object -First 1
if (-not $lanIp) { $lanIp = $candidates | Select-Object -First 1 }
if (-not $lanIp) {
  Write-Host "Could not find a network IP. Are you connected to Wi-Fi?" -ForegroundColor Red
  exit 1
}

$allowedHosts = "localhost,127.0.0.1,10.0.2.2,$lanIp"
$corsOrigins = "http://localhost:4300,http://127.0.0.1:4300,http://localhost:4400,http://127.0.0.1:4400,http://localhost:4401,http://127.0.0.1:4401,http://${lanIp}:4400,http://${lanIp}:4401,http://localhost,https://localhost,capacitor://localhost"

# Django backend on all network interfaces so another device can reach it.
$backendCommand = "`$env:DJANGO_ALLOWED_HOSTS='$allowedHosts'; `$env:CORS_ALLOWED_ORIGINS='$corsOrigins'; Set-Location '$backend'; .\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000"
Start-Process powershell -ArgumentList '-NoExit', '-Command', $backendCommand

# Angular frontend on all network interfaces. The mobile project is not started.
$frontendCommand = "Set-Location '$frontend'; npm start -- --host 0.0.0.0 --port 4400"
Start-Process powershell -ArgumentList '-NoExit', '-Command', $frontendCommand

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Backend and web frontend are starting." -ForegroundColor Cyan
Write-Host "  The mobile project is not being started." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Open on this PC or a phone on the same Wi-Fi:" -ForegroundColor Green
Write-Host ""
Write-Host "      http://${lanIp}:4400" -ForegroundColor Yellow
Write-Host ""
Write-Host "  If Windows Firewall asks, click Allow." -ForegroundColor Cyan
Write-Host "  Press Ctrl+C in both new windows to stop." -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
