# Run ONCE. Makes the helper start by itself every time you sign in, and relaunch within 5 minutes if it ever stops.
# Then it checks the other things that need to start with your PC.
$name = "PCRemoteWatcher"
$user = "$env:USERDOMAIN\$env:USERNAME"

Set-Location $PSScriptRoot
Copy-Item watcher.ps1 C:\pc-remote-trigger\watcher.ps1 -Force   # make sure the helper is the latest version
# conhost --headless runs PowerShell with no window at all (avoids Windows 11 terminal-window problems)
$a  = New-ScheduledTaskAction -Execute "conhost.exe" -Argument '--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\pc-remote-trigger\watcher.ps1"'
$t1 = New-ScheduledTaskTrigger -AtLogOn -User $user
$t2 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 9999)
$s  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -StartWhenAvailable -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $name -Action $a -Trigger $t1, $t2 -Settings $s -Force | Out-Null
Start-ScheduledTask -TaskName $name
Write-Host "OK   Helper task registered (starts at sign-in, relaunches if it stops)"
Start-Sleep -Seconds 8
Write-Host ("     State: " + (Get-ScheduledTask -TaskName $name).State + "   (should say Running)")
Write-Host "     --- helper log ---"
Get-Content C:\pc-remote-trigger\watcher.log -Tail 6

# --- checks ---
$run = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
if ($run."Docker Desktop") { Write-Host "OK   Docker Desktop starts when you sign in" }
else { Write-Host "FIX  Docker Desktop > Settings > General > turn on 'Start Docker Desktop when you sign in'" }

$ts = Get-Service Tailscale -ErrorAction SilentlyContinue
if ($ts -and $ts.StartType -eq "Automatic") { Write-Host "OK   Tailscale starts with Windows" }
else { Write-Host "FIX  Tailscale is not set to start automatically (reinstall it or check its settings)" }

$auto = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction SilentlyContinue).AutoAdminLogon
if ($auto -eq "1") { Write-Host "OK   Windows signs in automatically after a restart" }
else { Write-Host "NOTE Windows waits at the sign-in screen after a restart. Nothing starts until you sign in (see auto sign-in)." }
