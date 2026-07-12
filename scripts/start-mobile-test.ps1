# Starts everything needed to test the MOBILE app from your phone over Wi-Fi.
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\start-mobile-test.ps1
#
# It opens two windows (backend + mobile server) and prints the URL to type
# into your phone's browser. Phone and PC must be on the same Wi-Fi.

$workspace = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $workspace "backend"
$mobile = Join-Path $workspace "mobile"

# --- find this PC's Wi-Fi IPv4 (prefers 192.168.x.x) ---
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
$corsOrigins = "http://localhost:4300,http://127.0.0.1:4300,http://localhost:4400,http://127.0.0.1:4400,http://localhost,capacitor://localhost,http://${lanIp}:4400"

# --- backend: Django on 0.0.0.0:8000 so the phone can reach it ---
$backendCommand = "`$env:DJANGO_ALLOWED_HOSTS='$allowedHosts'; `$env:CORS_ALLOWED_ORIGINS='$corsOrigins'; Set-Location '$backend'; .\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000"
Start-Process powershell -ArgumentList '-NoExit', '-Command', $backendCommand

# --- mobile dev server on 0.0.0.0:4400 ---
$mobileCommand = "Set-Location '$mobile'; npm start -- --host 0.0.0.0"
Start-Process powershell -ArgumentList '-NoExit', '-Command', $mobileCommand

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Two windows are starting (backend + mobile)." -ForegroundColor Cyan
Write-Host ""
Write-Host "  ON YOUR PHONE, open:" -ForegroundColor Green
Write-Host ""
Write-Host "      http://${lanIp}:4400" -ForegroundColor Yellow
Write-Host ""
Write-Host "  (Phone must be on the same Wi-Fi as this PC.)" -ForegroundColor Cyan
Write-Host "  If Windows Firewall asks, click ALLOW for both." -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
