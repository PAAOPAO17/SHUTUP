# PC Remote - removes everything Setup installed.
$ErrorActionPreference = "Continue"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""; exit }

Write-Host "Removing PC Remote..."
Stop-ScheduledTask -TaskName "PCRemoteWatcher" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "PCRemoteWatcher" -Confirm:$false -ErrorAction SilentlyContinue
$dockerBin = "$env:ProgramFiles\Docker\Docker\resources\bin"
if (Test-Path $dockerBin) { $env:Path += ";$dockerBin" }
if (Test-Path "C:\pc-remote\docker-compose.yml") { Push-Location "C:\pc-remote"; docker compose down -v; Pop-Location }
$ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $ts) { & $ts serve reset }
Remove-MpPreference -ExclusionPath "C:\pc-remote-trigger\watcher.ps1" -ErrorAction SilentlyContinue
Remove-Item "C:\pc-remote", "C:\pc-remote-trigger" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Done. (Docker Desktop and Tailscale were left installed.)" -ForegroundColor Green
Read-Host "Press Enter to close"
