# Runs on Windows: shuts down on request, and streams the screen while someone is viewing.
# Writes C:\pc-remote-trigger\watcher.log so problems are visible.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Native {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    // milliseconds since the last keyboard / mouse / touch input
    public static uint IdleMs() {
        LASTINPUTINFO i = new LASTINPUTINFO();
        i.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref i)) return 0;
        return unchecked((uint)Environment.TickCount - i.dwTime);
    }
}
"@
[Native]::SetProcessDPIAware() | Out-Null

$dir = "C:\pc-remote-trigger"
$f = "$dir\shutdown"; $hb = "$dir\view"; $img = "$dir\screen.jpg"; $tmp = "$dir\screen.tmp"; $logf = "$dir\watcher.log"; $msgf = "$dir\message.txt"; $clrf = "$dir\message.clear"
Remove-Item $f, $hb, $img, $tmp, "$dir\message.txt", "$dir\message.tmp", "$dir\message.clear", "$dir\activity.txt", "$dir\activity.tmp" -Force -ErrorAction SilentlyContinue
Set-Content $logf ""
function Log($m) { Add-Content $logf ("{0} {1}" -f (Get-Date -Format "HH:mm:ss"), $m) }
Log "watcher started (pid $PID)"

# quality profiles: picture width, JPEG quality, pause between frames (ms)
$profiles = @{
    low  = @{ w = 640;  q = 40; ms = 110 }   # mobile data
    med  = @{ w = 960;  q = 50; ms = 45 }
    high = @{ w = 1280; q = 60; ms = 15 }    # Wi-Fi
}
$jpg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$q = New-Object System.Drawing.Imaging.EncoderParameters(1)
$q.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]50)
$md5 = [System.Security.Cryptography.MD5]::Create()
$bmp = $null; $wasViewing = $false; $lastErr = ""; $lastAlive = [datetime]::MinValue
# activity alert: PC idle for $idleLimit seconds, then used again -> tell the container (which notifies your phone)
$idleLimit = 300; $wasIdle = $false; $maxIdle = 0; $lastIdleCheck = [datetime]::MinValue
$actf = "$dir\activity.txt"; $actTmp = "$dir\activity.tmp"
$curProf = ""; $prof = "med"; $lastProfCheck = [datetime]::MinValue; $lastHash = ""; $cfg = $profiles["med"]

function Stop-Capture {
    foreach ($o in $script:gs, $script:small, $script:g, $script:bmp) { if ($o) { $o.Dispose() } }
    $script:bmp = $null
}


# Overlay window that never takes keyboard focus (falls back to a normal window if this can't compile)
$overlayOk = $true
try {
    Add-Type -ErrorAction Stop -WarningAction SilentlyContinue -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System.Windows.Forms;
public class OverlayForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams p = base.CreateParams; p.ExStyle |= 0x80 | 0x08000000; return p; }
    }
}
"@
} catch { $overlayOk = $false; Log "overlay fallback: $($_.Exception.Message)" }

# Shows plain text (no background) in the middle of the screen. White text with a thin dark outline so it
# is readable on any wallpaper. Click the text to dismiss; it also goes away after 30 minutes.
function Show-Message($text) {
    if ($script:form) { $script:form.Close(); $script:form = $null }
    $key = [System.Drawing.Color]::FromArgb(1, 2, 3)   # this colour is made fully transparent
    if ($script:overlayOk) { $fm = New-Object OverlayForm } else { $fm = New-Object System.Windows.Forms.Form }
    $fm.FormBorderStyle = "None"; $fm.TopMost = $true; $fm.ShowInTaskbar = $false
    $fm.BackColor = $key; $fm.TransparencyKey = $key
    $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $size = 24; if ($text.Length -lt 120) { $size = 34 }; if ($text.Length -lt 40) { $size = 48 }
    $font = New-Object System.Drawing.Font("Segoe UI", $size, [System.Drawing.FontStyle]::Bold)
    $bm = New-Object System.Drawing.Bitmap 1, 1
    $mg = [System.Drawing.Graphics]::FromImage($bm)
    $m = $mg.MeasureString($text, $font, [int]($area.Width * 0.8))
    $mg.Dispose(); $bm.Dispose()
    $fw = [Math]::Min([int]$m.Width + 40, $area.Width); $fh = [Math]::Min([int]$m.Height + 40, $area.Height)
    $fm.StartPosition = "Manual"
    $fm.Bounds = New-Object System.Drawing.Rectangle(($area.Left + [int](($area.Width - $fw) / 2)), ($area.Top + [int](($area.Height - $fh) / 2)), $fw, $fh)
    $fm.Tag = @{ Text = $text; Font = $font }
    $fm.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center; $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        foreach ($d in @(@(-2, 0), @(2, 0), @(0, -2), @(0, 2), @(-2, -2), @(2, -2), @(-2, 2), @(2, 2))) {
            $o = New-Object System.Drawing.RectangleF($d[0], $d[1], $s.ClientSize.Width, $s.ClientSize.Height)
            $g.DrawString($s.Tag.Text, $s.Tag.Font, [System.Drawing.Brushes]::Black, $o, $sf)
        }
        $r = New-Object System.Drawing.RectangleF(0, 0, $s.ClientSize.Width, $s.ClientSize.Height)
        $g.DrawString($s.Tag.Text, $s.Tag.Font, [System.Drawing.Brushes]::White, $r, $sf)
    })
    $fm.Add_Click({ if ($script:form) { $script:form.Close() } })
    $fm.Add_FormClosed({ $script:form = $null })
    $fm.Show()
    $script:form = $fm; $script:formEnd = (Get-Date).AddMinutes(30)
}
$form = $null; $formEnd = [datetime]::MinValue

try {
while ($true) {
    if (((Get-Date) - $lastAlive).TotalSeconds -ge 2) {   # "I'm running" signal for the app
        try { Set-Content "$dir\alive" (Get-Date -Format o) } catch { }
        $lastAlive = Get-Date
    }
    if (((Get-Date) - $lastIdleCheck).TotalMilliseconds -ge 1000) {   # idle / activity detection
        $lastIdleCheck = Get-Date
        $idle = [Native]::IdleMs() / 1000
        if ($idle -ge $idleLimit) {
            $wasIdle = $true
            if ($idle -gt $maxIdle) { $maxIdle = $idle }
        } elseif ($wasIdle) {   # was idle long enough, and there was input since
            try {
                [System.IO.File]::WriteAllText($actTmp, [string][int]$maxIdle)
                Move-Item $actTmp $actf -Force
                Log ("activity after {0} s idle" -f [int]$maxIdle)
            } catch { }
            $wasIdle = $false; $maxIdle = 0
        }
    }
    [System.Windows.Forms.Application]::DoEvents()
    if ($form -and (Get-Date) -gt $formEnd) { $form.Close(); $form = $null }
    if (Test-Path $clrf) {   # "remove message" from the phone
        Remove-Item $clrf -Force -ErrorAction SilentlyContinue
        if ($form) { $form.Close(); $form = $null }
        Log "message cleared"
    }
    if (Test-Path $msgf) {
        try {
            $text = [System.IO.File]::ReadAllText($msgf, [System.Text.Encoding]::UTF8)
            Remove-Item $msgf -Force
            Log "message shown"
            Show-Message $text
        } catch { }   # file briefly in use: try again next loop
    }
    if (Test-Path $f) { Log "shutdown requested"; Remove-Item $f -Force; shutdown.exe /s /t 0 /f; break }

    $viewing = (Test-Path $hb) -and ([Math]::Abs(((Get-Date) - (Get-Item $hb).LastWriteTime).TotalSeconds) -lt 8)
    if ($viewing -and -not $wasViewing) { Log "viewing started" }
    if (-not $viewing -and $wasViewing) { Log "viewing stopped" }
    $wasViewing = $viewing

    if ($viewing) {
        $delay = 30
        try {
            # the phone's chosen quality is written into the "view" file by the container
            if (((Get-Date) - $lastProfCheck).TotalMilliseconds -gt 500) {
                $lastProfCheck = Get-Date
                try { $p = (Get-Content $hb -Raw -ErrorAction Stop).Trim() } catch { $p = $prof }
                if (-not $profiles.ContainsKey($p)) { $p = "med" }
                if ($p -ne $curProf) {
                    Stop-Capture
                    $curProf = $p; $prof = $p; $cfg = $profiles[$p]; $lastHash = ""
                    $q.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$cfg.q)
                    Log "quality: $p"
                }
            }
            $delay = [int]$cfg.ms

            if (-not $bmp) {   # set up once per session / quality change, reuse for every frame
                $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
                $w = [Math]::Min([int]$cfg.w, $b.Width); $h = [int]($b.Height * $w / $b.Width)
                $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $small = New-Object System.Drawing.Bitmap $w, $h
                $gs = [System.Drawing.Graphics]::FromImage($small)
                $gs.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::Low
            }
            $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
            $gs.DrawImage($bmp, 0, 0, $w, $h)
            $ms = New-Object System.IO.MemoryStream
            $small.Save($ms, $jpg, $q)
            $bytes = $ms.ToArray(); $ms.Dispose()

            # only send a frame if the screen actually changed (saves data when idle)
            $hash = [Convert]::ToBase64String($md5.ComputeHash($bytes))
            if ($hash -ne $lastHash) {
                $lastHash = $hash
                [System.IO.File]::WriteAllBytes($tmp, $bytes)
                try { Move-Item $tmp $img -Force } catch { }   # reader briefly using the file: skip this frame
            }
        } catch {
            $err = $_.Exception.Message
            if ($err -ne $lastErr) { Log "capture error: $err"; $lastErr = $err }
            Stop-Capture
            Start-Sleep -Milliseconds 500
        }
        Start-Sleep -Milliseconds $delay
    } else {
        if ($bmp) { Stop-Capture }
        $curProf = ""
        Remove-Item $img -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds $(if ($form) { 50 } else { 400 })
    }
}
} catch { Log "FATAL: $($_.Exception.Message)" } finally { Log "watcher stopped" }
