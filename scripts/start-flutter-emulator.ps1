<#
.SYNOPSIS
  Starts the CoachFlow Flutter Android emulator, sized and positioned to fit.

.DESCRIPTION
  The Pixel 7 AVD renders at 1080x2400. This screen has ~912px of usable height,
  so at 1:1 the emulator is nearly three times too tall and Windows parks it
  partly above the top edge (observed at top=-601), leaving only a sliver
  visible. The AVD also stores window.scale = -1 ("no scaling"), so the size
  resets on every launch no matter what was set last time.

  This script launches with an explicit scale and then forces the window onto
  the screen once it appears, which the emulator does not do reliably itself.

.EXAMPLE
  .\scripts\start-flutter-emulator.ps1
  .\scripts\start-flutter-emulator.ps1 -Scale 0.25          # smaller
  .\scripts\start-flutter-emulator.ps1 -Run                 # also flutter run
#>
[CmdletBinding()]
param(
  [string]$Avd = 'coachflow_pixel',
  [double]$Scale = 0.30,
  [int]$Left = 570,
  [int]$Top = 0,
  # Also build+install the app and attach for hot reload once booted.
  [switch]$Run,
  # Cold boot, ignoring the saved snapshot. Use when the emulator has wedged -
  # a symptom is input dying and screenshots coming back black, with
  # "Application Not Responding: system" holding window focus.
  [switch]$ColdBoot,
  # Kill a running emulator first. `adb emu kill` does not always take; this
  # kills the qemu process outright.
  [switch]$Force,
  # Emulator reaches this PC on 10.0.2.2; localhost would mean the emulator.
  [string]$ApiBaseUrl = 'http://10.0.2.2:8000'
)

$ErrorActionPreference = 'Stop'

$sdk = "$env:LOCALAPPDATA\Android\Sdk"
$emulatorExe = "$sdk\emulator\emulator.exe"
$adb = "$sdk\platform-tools\adb.exe"

if (-not (Test-Path $emulatorExe)) { throw "emulator.exe not found at $emulatorExe" }

# --- force kill first? ---
if ($Force) {
  Get-Process | Where-Object { $_.ProcessName -like '*qemu*' -or $_.ProcessName -like '*emulator*' } |
    ForEach-Object { Write-Host "Killing $($_.ProcessName) ($($_.Id))" -ForegroundColor Yellow; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 4
  & $adb kill-server 2>$null | Out-Null
  Start-Sleep -Seconds 2
  & $adb start-server 2>$null | Out-Null
}

# --- already running? ---
$running = (& $adb devices) -match 'emulator-\d+\s+device'
if ($running) {
  Write-Host "Emulator already running - repositioning only." -ForegroundColor Yellow
} else {
  # Always launch through here rather than calling emulator.exe directly: the
  # AVD stores window.scale = -1, so a direct launch reverts to full 1080x2400
  # and Windows parks it above the top of the screen.
  $args = @('-avd', $Avd, '-scale', $Scale)
  if ($ColdBoot) { $args += '-no-snapshot-load' }
  Write-Host "Launching $Avd at scale $Scale$(if ($ColdBoot) { ' (cold boot)' }) ..." -ForegroundColor Cyan
  Start-Process -FilePath $emulatorExe -ArgumentList $args

  Write-Host "Waiting for boot (first start can take a minute) ..." -ForegroundColor Cyan
  $deadline = (Get-Date).AddMinutes(5)
  do {
    Start-Sleep -Seconds 3
    $booted = (& $adb shell getprop sys.boot_completed 2>$null) -replace '\s', ''
    if ((Get-Date) -gt $deadline) { throw 'Emulator did not boot within 5 minutes.' }
  } until ($booted -eq '1')
  Write-Host "Booted." -ForegroundColor Green

  # The Android 35 image pops a stylus tutorial that swallows scripted input.
  & $adb shell settings put secure stylus_handwriting_enabled 0 2>$null | Out-Null
}

# --- force the window on-screen ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class EmuWin {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@ -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Windows.Forms
$work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

# Device is 1080x2400; leave headroom for the title bar and side toolbar.
$w = [int](1080 * $Scale) + 60
$h = [math]::Min([int](2400 * $Scale) + 90, $work.Height - 20)

$win = $null
$tries = 0
while ($null -eq $win -and $tries -lt 20) {
  Start-Sleep -Seconds 1
  $win = Get-Process | Where-Object { $_.MainWindowTitle -like '*Android Emulator*' } | Select-Object -First 1
  $tries++
}

if ($null -eq $win) {
  Write-Warning 'Emulator window not found - it may still be starting. Reposition by re-running this script.'
} else {
  [void][EmuWin]::MoveWindow($win.MainWindowHandle, $Left, $Top, $w, $h, $true)
  Start-Sleep -Seconds 1
  [void][EmuWin]::SetForegroundWindow($win.MainWindowHandle)
  Write-Host "Window placed at ${Left},${Top} size ${w}x${h} (screen $($work.Width)x$($work.Height))." -ForegroundColor Green
}

if ($Run) {
  $proj = Join-Path (Split-Path $PSScriptRoot -Parent) 'mobile_flutter'
  Write-Host "`nRunning the app (r = hot reload, q = quit) ..." -ForegroundColor Cyan
  Write-Host "Reminder: the Django backend must be on :8000 for login to work.`n" -ForegroundColor Yellow
  Push-Location $proj
  try {
    & flutter run -d emulator-5554 --dart-define=API_BASE_URL=$ApiBaseUrl
  } finally {
    Pop-Location
  }
} else {
  Write-Host "`nNext:" -ForegroundColor Cyan
  Write-Host "  cd mobile_flutter"
  Write-Host "  flutter run -d emulator-5554 --dart-define=API_BASE_URL=$ApiBaseUrl"
  Write-Host "  (or re-run this script with -Run to do both)"
}
