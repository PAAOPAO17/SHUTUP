# Run this after replacing files in the SHUTUP folder. It applies everything in one go:
#   powershell -ExecutionPolicy Bypass -File .\update.ps1
Set-Location $PSScriptRoot
Copy-Item watcher.ps1 C:\pc-remote-trigger\watcher.ps1 -Force      # new helper script
Stop-ScheduledTask -TaskName "PCRemoteWatcher" -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName "PCRemoteWatcher"                    # restart the helper
docker compose up -d --build                                       # rebuild the website
Write-Host "Done. Close and reopen the app on your phone."
