$Script:Report = [System.Collections.Generic.List[string]]::new()
$Script:LogFile = $null
$Script:StartFree = 0
$Script:EndFree = 0
$Script:DoCleanup = $true
$Script:DoUpdates = $true
$Script:DoWinUpdate = $true
$Script:DoWinget = $true
$Script:DoRepair = $false
$Script:DoRestorePoint = $true
$Script:DoAmd = $true
$Script:DoShaderCleanup = $false
$Script:DoGamingOptimize = $true
$Script:TotalSteps = 0
$Script:CurrentStep = 0
$Script:RunStart = Get-Date
$Script:StepNames = [System.Collections.Generic.List[string]]::new()
$Script:TempOlderThanDays = 2
$Script:Ui = $null
$Script:CancelRequested = $false
$Script:LastPumpUtc = [datetime]::MinValue
$Script:LastProgressPct = 0

function Pump-Ui {
    $form = Get-UiControl Form
    if ($form -and -not $form.IsDisposed) {
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Pump-UiThrottled {
    $now = [datetime]::UtcNow
    if (($now - $Script:LastPumpUtc).TotalMilliseconds -lt 300) { return }
    $Script:LastPumpUtc = $now
    Pump-Ui
}

function Get-UiControl([string]$Name) {
    if (-not $Script:Ui) { return $null }
    return $Script:Ui.$Name
}

function Set-UiProgressValue([int]$Value) {
    $pct = [math]::Max(0, [math]::Min(100, $Value))
    $Script:LastProgressPct = $pct
    $bar = Get-UiControl Progress
    if ($bar) {
        try { $bar.Value = $pct } catch { }
    }
    $fill = Get-UiControl ProgressFill
    $track = Get-UiControl ProgressTrack
    if ($fill -and $track) {
        $w = [math]::Max(0, [int](($track.ClientSize.Width * $pct) / 100.0))
        $fill.Width = $w
    }
}

function Set-UiStatusText([string]$Text) {
    $lbl = Get-UiControl Status
    if ($lbl) { $lbl.Text = $Text }
}

function Invoke-WithUiWait {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Activity = "Working",
        [int]$TimeoutSec = 900,
        [object[]]$ArgumentList = @()
    )
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($ScriptBlock)
    foreach ($a in $ArgumentList) {
        [void]$ps.AddArgument($a)
    }
    $handle = $ps.BeginInvoke()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $spin = @('|','/','-','\')
    $i = 0
    try {
        while (-not $handle.IsCompleted) {
            if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) {
                try { $ps.Stop() } catch { }
                Write-Warn "$Activity timed out after ${TimeoutSec}s"
                return $null
            }
            $sec = [int]$sw.Elapsed.TotalSeconds
            $ch = $spin[$i % 4]
            Set-UiStatusText ("[{0}] {1}... {2}s" -f $ch, $Activity, $sec)
            Write-Host -NoNewline ("`r  [{0}] {1}... {2}s   " -f $ch, $Activity, $sec) -ForegroundColor DarkYellow
            Pump-Ui
            Start-Sleep -Milliseconds 200
            $i++
        }
        Write-Host ""
        $result = $ps.EndInvoke($handle)
        if ($ps.HadErrors) {
            foreach ($e in $ps.Streams.Error) {
                Write-Log ("ASYNC_ERR: " + $e.ToString())
            }
        }
        return $result
    } finally {
        $ps.Dispose()
        $rs.Dispose()
    }
}

function Get-AsyncResultText {
    param($Result)
    if ($null -eq $Result) { return $null }
    if ($Result -is [string]) { return $Result }
    $arr = @($Result)
    if ($arr.Count -eq 0) { return "" }
    return [string]$arr[-1]
}

function Ensure-Admin {
    param(
        [string]$ScriptPath = "",
        [string]$RelaunchArgs = ""
    )
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]::new($id)
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }

    if (-not $ScriptPath) { $ScriptPath = $PSCommandPath }
    if (-not $ScriptPath -or -not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Cannot elevate: script path not found."
    }

    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $hideGui = ($RelaunchArgs -match '-Mode\s+Gui')
    $arguments = "-NoProfile -ExecutionPolicy Bypass -STA"
    if ($hideGui) { $arguments += " -WindowStyle Hidden" }
    $arguments += " -File `"$ScriptPath`""
    if ($RelaunchArgs) { $arguments += " $RelaunchArgs" }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = (Split-Path -Parent $ScriptPath)
    $psi.Verb = "runas"
    $psi.UseShellExecute = $true

    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        throw "Elevation cancelled or failed: $($_.Exception.Message)"
    }
    exit 0
}

function Init-Log {
    $dir = Join-Path $env:USERPROFILE "Desktop\PC-Maintenance-Logs"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $Script:LogFile = Join-Path $dir "maintenance_$stamp.log"
    "PC Maintenance Kit v5 started: $(Get-Date)" | Out-File $Script:LogFile -Encoding UTF8
}

function Write-Log([string]$msg) {
    if ($Script:LogFile) {
        "$(Get-Date -Format 'HH:mm:ss')  $msg" | Out-File $Script:LogFile -Append -Encoding UTF8
    }
}

function Get-Elapsed {
    $ts = (Get-Date) - $Script:RunStart
    return "{0:00}:{1:00}" -f [int]$ts.TotalMinutes, $ts.Seconds
}

function Update-UiProgress {
    param([string]$Label = "")
    if ($Script:TotalSteps -le 0) {
        if ($Label) { Set-UiStatusText -Text $Label }
        if (Get-Command Update-GuiStatusBar -EA SilentlyContinue) { Update-GuiStatusBar -JobText $Label }
        return
    }
    $pct = [math]::Min(100, [math]::Round(($Script:CurrentStep / $Script:TotalSteps) * 100))
    Set-UiProgressValue -Value ([int]$pct)
    $plain = ("Running: {0}  ·  {1}/{2}  ·  {3}" -f $Label, $Script:CurrentStep, $Script:TotalSteps, (Get-Elapsed))
    Set-UiStatusText -Text $plain
    if (Get-Command Update-GuiStatusBar -EA SilentlyContinue) {
        Update-GuiStatusBar -JobText $plain
    }
    try {
        $host.UI.RawUI.WindowTitle = "PC Maintenance Kit  $pct%  $($Script:CurrentStep)/$($Script:TotalSteps)  $(Get-Elapsed)"
    } catch { }
    Pump-Ui
}

function Append-UiLog {
    param([string]$msg, [string]$ColorName = "White")
    $box = Get-UiControl Log
    if (-not $box) { return }
    $color = switch ($ColorName) {
        'Green'  { [System.Drawing.Color]::FromArgb(80, 200, 120) }
        'Yellow' { [System.Drawing.Color]::FromArgb(230, 180, 60) }
        'Red'    { [System.Drawing.Color]::FromArgb(230, 90, 90) }
        'Cyan'   { [System.Drawing.Color]::FromArgb(80, 190, 220) }
        'Gray'   { [System.Drawing.Color]::FromArgb(140, 150, 160) }
        default  { [System.Drawing.Color]::FromArgb(220, 225, 230) }
    }
    $stamp = Get-Date -Format "HH:mm:ss"
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $color
    $box.AppendText("[$stamp] $msg`r`n")
    $box.SelectionStart = $box.TextLength
    $box.ScrollToCaret()
    Pump-Ui
}

function Write-Step([string]$msg) {
    $Script:CurrentStep++
    Write-Host ""
    Write-Host "=== [$($Script:CurrentStep)/$($Script:TotalSteps)] $msg ===" -ForegroundColor Cyan
    Update-UiProgress -Label $msg
    Append-UiLog (">> [{0}/{1}] {2}" -f $Script:CurrentStep, $Script:TotalSteps, $msg) "Cyan"
    Write-Log "STEP $($Script:CurrentStep)/$($Script:TotalSteps): $msg"
}

function Write-Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
    $Script:Report.Add("[OK] $msg") | Out-Null
    Append-UiLog "  [OK] $msg" "Green"
    Write-Log "OK: $msg"
}

function Write-Warn([string]$msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
    $Script:Report.Add("[!] $msg") | Out-Null
    Append-UiLog "  [!] $msg" "Yellow"
    Write-Log "WARN: $msg"
}

function Write-Fail([string]$msg) {
    Write-Host "  [X] $msg" -ForegroundColor Red
    $Script:Report.Add("[X] $msg") | Out-Null
    Append-UiLog "  [X] $msg" "Red"
    Write-Log "FAIL: $msg"
}

function Write-Info([string]$msg) {
    Write-Host "  ... $msg" -ForegroundColor DarkGray
    Append-UiLog "  ... $msg" "Gray"
    Write-Log "INFO: $msg"
}

function Get-CFreeGB {
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    return [math]::Round($d.FreeSpace / 1GB, 1)
}

function Test-RebootPending {
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { return $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { return $true }
    try {
        $pfr = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -EA SilentlyContinue
        if ($pfr -and $pfr.PendingFileRenameOperations) { return $true }
    } catch { }
    return $false
}

function Wait-WithSpinner {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSec = 120,
        [string]$Activity = "Working"
    )
    $spin = @('|','/','-','\')
    $i = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $Process.HasExited) {
        if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) {
            Write-Host ""
            try { $Process.Kill() } catch { }
            Write-Warn "$Activity timed out after ${TimeoutSec}s - skipped"
            return $false
        }
        $ch = $spin[$i % 4]
        $sec = [int]$sw.Elapsed.TotalSeconds
        Write-Host -NoNewline ("`r  [{0}] {1}... {2}s / {3}s max   " -f $ch, $Activity, $sec, $TimeoutSec) -ForegroundColor DarkYellow
        if ($Script:Ui) {
            Set-UiStatusText -Text ("[{0}] {1}... {2}s / {3}s" -f $ch, $Activity, $sec, $TimeoutSec)
        }
        Pump-Ui
        Start-Sleep -Milliseconds 250
        $i++
    }
    Write-Host -NoNewline "`r"
    Write-Host ("  [OK] {0} finished in {1}s                    " -f $Activity, [int]$sw.Elapsed.TotalSeconds) -ForegroundColor Green
    return $true
}

function Apply-ModeFlags {
    param(
        [ValidateSet('Full','CleanupOnly','UpdatesOnly','Repair','FullRepair')]
        [string]$ModeName
    )
    switch ($ModeName) {
        'Full' {
            $Script:DoCleanup=$true; $Script:DoUpdates=$true; $Script:DoWinUpdate=$false; $Script:DoWinget=$false
            $Script:DoRepair=$false; $Script:DoRestorePoint=$true; $Script:DoAmd=$false
            $Script:DoShaderCleanup=$true; $Script:DoGamingOptimize=$true
        }
        'CleanupOnly' {
            $Script:DoCleanup=$true; $Script:DoUpdates=$false; $Script:DoWinUpdate=$false; $Script:DoWinget=$false
            $Script:DoRepair=$false; $Script:DoRestorePoint=$false; $Script:DoAmd=$false
            $Script:DoShaderCleanup=$true; $Script:DoGamingOptimize=$false
        }
        'UpdatesOnly' {
            $Script:DoCleanup=$false; $Script:DoUpdates=$true; $Script:DoWinUpdate=$true; $Script:DoWinget=$true
            $Script:DoRepair=$false; $Script:DoRestorePoint=$true; $Script:DoAmd=$true
            $Script:DoShaderCleanup=$false; $Script:DoGamingOptimize=$false
        }
        'Repair' {
            $Script:DoCleanup=$false; $Script:DoUpdates=$false; $Script:DoWinUpdate=$false; $Script:DoWinget=$false
            $Script:DoRepair=$true; $Script:DoRestorePoint=$true; $Script:DoAmd=$false
            $Script:DoShaderCleanup=$false; $Script:DoGamingOptimize=$false
        }
        'FullRepair' {
            $Script:DoCleanup=$true; $Script:DoUpdates=$true; $Script:DoWinUpdate=$true; $Script:DoWinget=$true
            $Script:DoRepair=$true; $Script:DoRestorePoint=$true; $Script:DoAmd=$true
            $Script:DoShaderCleanup=$true; $Script:DoGamingOptimize=$true
        }
    }
}

function Build-StepPlan {
    $Script:StepNames.Clear()
    if ($Script:DoRestorePoint) { [void]$Script:StepNames.Add("Restore point") }
    if ($Script:DoCleanup) {
        [void]$Script:StepNames.Add("Temp cleanup")
        [void]$Script:StepNames.Add("Browser caches")
        [void]$Script:StepNames.Add("Recycle Bin")
    }
    if ($Script:DoShaderCleanup) { [void]$Script:StepNames.Add("GPU shader caches") }
    if ($Script:DoWinUpdate) { [void]$Script:StepNames.Add("Windows Update") }
    if ($Script:DoWinget) { [void]$Script:StepNames.Add("winget upgrades") }
    if ($Script:DoAmd) { [void]$Script:StepNames.Add("AMD Adrenalin") }
    if ($Script:DoRepair) { [void]$Script:StepNames.Add("DISM + SFC repair") }
    if ($Script:DoGamingOptimize) { [void]$Script:StepNames.Add("Gaming optimize") }
    [void]$Script:StepNames.Add("Health checks")
    $Script:TotalSteps = $Script:StepNames.Count
    $Script:CurrentStep = 0
}

function New-MaintenanceRestorePoint {
    Write-Step "Creating System Restore Point"
    Write-Info "This usually takes 10-60 seconds..."
    $result = Invoke-WithUiWait -Activity "Creating restore point" -TimeoutSec 180 -ScriptBlock {
        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description ("PC Maintenance " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            "OK"
        } catch {
            "ERR:" + $_.Exception.Message
        }
    }
    $text = Get-AsyncResultText $result
    if ($null -eq $text) {
        Write-Warn "Restore point skipped (timeout)"
    } elseif ($text -eq "OK") {
        Write-Ok "Restore point created"
    } elseif ($text -like "ERR:*") {
        Write-Warn ("Restore point skipped: " + $text.Substring(4))
    } else {
        Write-Warn "Restore point skipped"
    }
}

function Remove-OldFilesInPath {
    param([string]$Path, [int]$OlderThanDays, [switch]$DeleteFoldersToo)
    if (-not (Test-Path $Path)) { return 0 }
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $freed = 0L
    $n = 0
    Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            try { $freed += $_.Length; Remove-Item $_.FullName -Force -ErrorAction Stop } catch { }
            $n++
            if (($n % 80) -eq 0) { Pump-UiThrottled }
        }
    if ($DeleteFoldersToo) {
        Get-ChildItem -Path $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            ForEach-Object {
                try {
                    if (-not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                } catch { }
            }
    }
    return $freed
}

function Invoke-TempCleanup {
    Write-Step "Cleaning temp files (older than $($Script:TempOlderThanDays) day(s))"
    $total = 0L
    $raw = @(
        $env:TEMP,
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows\Temp",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\AMD\Dx9Cache",
        "$env:LOCALAPPDATA\AMD\DxcCache"
    )
    $paths = @()
    $seen = @{}
    foreach ($p in $raw) {
        if (-not (Test-Path $p)) { continue }
        try {
            $full = (Resolve-Path $p -EA Stop).Path.ToLowerInvariant()
            if (-not $seen.ContainsKey($full)) { $seen[$full] = $true; $paths += $p }
        } catch { $paths += $p }
    }

    $i = 0
    foreach ($p in $paths) {
        $i++
        Write-Info ("[{0}/{1}] {2}" -f $i, $paths.Count, $p)
        $freed = Remove-OldFilesInPath -Path $p -OlderThanDays $Script:TempOlderThanDays -DeleteFoldersToo
        $total += $freed
        if ($freed -gt 1MB) {
            Write-Ok ("{0}: freed {1:N0} MB" -f (Split-Path $p -Leaf), ($freed / 1MB))
        }
    }

    try {
        if ($Script:DoWinUpdate) {
            Write-Info "Skipped Windows Update download-cache wipe (updates will run next)"
        } else {
            Write-Info "Clearing Windows Update download cache..."
            $do = "C:\Windows\SoftwareDistribution\Download"
            if (Test-Path $do) {
                $wuStopped = $false
                $bitsStopped = $false
                try {
                    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                    $wuStopped = $true
                    Stop-Service bits -Force -ErrorAction SilentlyContinue
                    $bitsStopped = $true
                    Start-Sleep -Seconds 2
                    $before = (Get-ChildItem $do -Recurse -Force -File -EA SilentlyContinue |
                        Measure-Object Length -Sum -EA SilentlyContinue).Sum
                    if (-not $before) { $before = 0 }
                    Get-ChildItem $do -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue
                    $total += $before
                    Write-Ok ("Update download cache: {0:N0} MB" -f ($before / 1MB))
                } finally {
                    if ($bitsStopped) { Start-Service bits -EA SilentlyContinue }
                    if ($wuStopped) { Start-Service wuauserv -EA SilentlyContinue }
                }
            }
        }
    } catch {
        Write-Warn "Update download cache partially skipped"
        Start-Service bits -EA SilentlyContinue
        Start-Service wuauserv -EA SilentlyContinue
    }

    if ($total -gt 1MB) {
        Write-Ok ("Temp cleanup total: {0:N1} GB" -f ($total / 1GB))
    } else {
        Write-Ok "Temp folders already clean"
    }
}

function Invoke-BrowserCacheCleanup {
    Write-Step "Cleaning browser caches"
    Write-Info "Close browsers for best results (locked files are skipped)"
    $total = 0L
    $browserPaths = [ordered]@{
        'Brave'   = @(
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\GPUCache",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\ShaderCache"
        )
        'Chrome'  = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
        )
        'Edge'    = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
        )
        'Firefox' = @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles")
    }

    foreach ($browser in $browserPaths.Keys) {
        Write-Info "Checking $browser..."
        $freedBrowser = 0L
        foreach ($p in $browserPaths[$browser]) {
            if (-not (Test-Path $p)) { continue }
            if ($browser -eq 'Firefox') {
                Get-ChildItem $p -Directory -EA SilentlyContinue | ForEach-Object {
                    $cache = Join-Path $_.FullName "cache2"
                    if (Test-Path $cache) {
                        $freedBrowser += Remove-OldFilesInPath -Path $cache -OlderThanDays 0 -DeleteFoldersToo
                    }
                }
            } else {
                $freedBrowser += Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
            }
        }
        if ($freedBrowser -gt 0) {
            $total += $freedBrowser
            Write-Ok ("{0}: freed {1:N0} MB" -f $browser, ($freedBrowser / 1MB))
        }
    }
    if ($total -gt 1MB) {
        Write-Ok ("Browser caches total: {0:N0} MB" -f ($total / 1MB))
    } else {
        Write-Ok "Browser caches already clean (or browsers were open)"
    }
}

function Invoke-RecycleAndCleanMgr {
    Write-Step "Recycle Bin"
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Ok "Recycle Bin emptied"
    } catch {
        Write-Warn "Recycle Bin empty or locked"
    }
}

function Invoke-WindowsUpdate {
    Write-Step "Windows Updates"
    Write-Info "Scan runs in the background so the window stays responsive (1-5 min)"
    try {
        $have = Get-Module -ListAvailable PSWindowsUpdate -EA SilentlyContinue
        if (-not $have) {
            Write-Info "Installing PSWindowsUpdate module (one-time)..."
            $installed = Invoke-WithUiWait -Activity "Installing update module" -TimeoutSec 300 -ScriptBlock {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -EA SilentlyContinue | Out-Null
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -EA SilentlyContinue
                    Install-Module PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers -EA Stop
                    "OK"
                } catch {
                    "ERR:" + $_.Exception.Message
                }
            }
            $instText = Get-AsyncResultText $installed
            if ($instText -ne "OK") {
                Write-Warn "Module install failed - using UsoClient fallback"
                UsoClient StartInteractiveScan 2>$null
                Write-Ok "Windows Update scan started (check Settings > Windows Update)"
                return
            }
            Write-Ok "PSWindowsUpdate installed"
        }

        Write-Info "Scanning for updates..."
        $scan = Invoke-WithUiWait -Activity "Scanning Windows Update" -TimeoutSec 600 -ScriptBlock {
            Import-Module PSWindowsUpdate -EA SilentlyContinue
            @(Get-WindowsUpdate -MicrosoftUpdate -EA SilentlyContinue | ForEach-Object { $_.Title })
        }
        if ($null -eq $scan) {
            Write-Warn "Windows Update scan timed out / failed"
            return
        }
        $titles = @($scan | Where-Object { $_ })
        if ($titles.Count -gt 0) {
            Write-Info ("Found {0} update(s). Installing..." -f $titles.Count)
            $n = 0
            foreach ($t in $titles) {
                $n++
                Write-Info ("Update {0}/{1}: {2}" -f $n, $titles.Count, $t)
            }
            $null = Invoke-WithUiWait -Activity "Installing Windows Updates" -TimeoutSec 3600 -ScriptBlock {
                Import-Module PSWindowsUpdate -EA SilentlyContinue
                Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -EA SilentlyContinue | Out-Null
                "OK"
            }
            Write-Ok "Windows Updates installed (reboot may be required)"
        } else {
            Write-Ok "Windows is up to date"
        }
    } catch {
        Write-Fail "Windows Update: $($_.Exception.Message)"
    }
}

function Invoke-WingetUpdates {
    Write-Step "Upgrading apps (winget)"
    try {
        $winget = (Get-Command winget -EA Stop).Source
        Write-Info "Scanning for app upgrades (background)..."
        $outObj = Invoke-WithUiWait -Activity "winget upgrade" -TimeoutSec 1200 -ArgumentList @($winget) -ScriptBlock {
            param([string]$WingetPath)
            & $WingetPath upgrade --all --accept-package-agreements --accept-source-agreements --disable-interactivity --include-unknown 2>&1 | Out-String
        }
        $out = Get-AsyncResultText $outObj
        if ($null -eq $out) {
            Write-Warn "winget timed out"
            return
        }
        Write-Log $out
        if ($out -match "No installed package found matching input criteria|No newer package versions") {
            Write-Ok "winget apps are up to date"
        } elseif ($out -match "Successfully installed") {
            $count = ([regex]::Matches($out, "Successfully installed")).Count
            Write-Ok ("winget upgraded {0} package(s)" -f $count)
        } else {
            Write-Ok "winget upgrade pass completed"
        }
    } catch {
        Write-Warn "winget not available or failed"
    }
}

function Invoke-AmdOpen {
    Write-Step "AMD Adrenalin"
    $amdPaths = @(
        "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe",
        "${env:ProgramFiles(x86)}\AMD\CNext\CNext\RadeonSoftware.exe"
    )
    $amd = $amdPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($amd) {
        try {
            Start-Process $amd
            Write-Ok "Opened AMD Adrenalin - check for driver updates"
        } catch {
            Write-Fail "Could not open AMD Adrenalin"
        }
    } else {
        Write-Warn "AMD Adrenalin not found (skipped)"
    }
}

function Invoke-ShaderCacheCleanup {
    Write-Step "Cleaning GPU shader caches"
    Write-Info "Games may rebuild shaders on next launch (one-time stutter)"
    $total = 0L
    $paths = @(
        "$env:LOCALAPPDATA\D3DSCache",
        "$env:LOCALAPPDATA\AMD\DxCache",
        "$env:LOCALAPPDATA\AMD\Dx9Cache",
        "$env:LOCALAPPDATA\AMD\DxcCache",
        "$env:LOCALAPPDATA\NVIDIA\DXCache",
        "$env:LOCALAPPDATA\NVIDIA\GLCache",
        "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"
    )
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        $freed = Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
        $total += $freed
        if ($freed -gt 1MB) {
            Write-Ok ("{0}: freed {1:N0} MB" -f (Split-Path $p -Leaf), ($freed / 1MB))
        }
    }
    if ($total -gt 1MB) {
        Write-Ok ("Shader caches total: {0:N0} MB" -f ($total / 1MB))
    } else {
        Write-Ok "Shader caches already light"
    }
}

function Invoke-LauncherCacheCleanup {
    param(
        [bool]$Steam = $false,
        [bool]$Epic = $false,
        [bool]$Riot = $false
    )
    Write-Step "Launcher download caches"
    $total = 0L
    if ($Steam) {
        $steamRoots = @(
            "C:\Program Files (x86)\Steam\steamapps\downloading",
            "D:\Steam\steamapps\downloading",
            "E:\Steam\steamapps\downloading"
        )
        foreach ($p in $steamRoots) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            Write-Info "Steam downloading: $p"
            $freed = Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
            $total += $freed
        }
    }
    if ($Epic) {
        $epic = @(
            "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache",
            "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache_4430",
            "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs"
        )
        foreach ($p in $epic) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $freed = Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
            $total += $freed
        }
    }
    if ($Riot) {
        $riot = @(
            "$env:LOCALAPPDATA\Riot Games\Riot Client\CefCache",
            "$env:LOCALAPPDATA\Riot Games\Riot Client\Logs"
        )
        foreach ($p in $riot) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $freed = Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
            $total += $freed
        }
    }
    if ($total -gt 1MB) {
        Write-Ok ("Launcher caches total: {0:N0} MB" -f ($total / 1MB))
    } else {
        Write-Ok "Launcher caches already clean (or paths not found)"
    }
}

function Invoke-NvidiaAppOpen {
    $paths = @(
        "$env:ProgramFiles\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe",
        "$env:ProgramFiles\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe",
        "${env:ProgramFiles(x86)}\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"
    )
    $exe = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) {
        Start-Process $exe
        Write-Ok "Opened NVIDIA app"
        return $true
    }
    Write-Warn "NVIDIA app not found"
    return $false
}

function Show-RebootRecommendedDialog {
    if (-not (Test-RebootPending)) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            "Windows has a pending restart (often after updates).`n`nRestart when you finish gaming for best stability.",
            "PC Maintenance - Restart recommended",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch { }
}

function Invoke-GamingChecks {
    Write-Step "Quick health / gaming checks"
    try {
        $disk = Get-PhysicalDisk | Select-Object -First 1
        Write-Ok ("SSD: {0} - {1}" -f $disk.FriendlyName, $disk.HealthStatus)
    } catch { }

    try {
        $power = (powercfg /getactivescheme) -replace '.*\((.+)\).*', '$1'
        Write-Ok "Power plan: $power"
    } catch { }

    $gamedvr = (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_Enabled -EA SilentlyContinue).GameDVR_Enabled
    if ($gamedvr -eq 0) {
        Write-Ok "Xbox Game DVR: Off"
    } else {
        Write-Warn "Xbox Game DVR was On - disabling..."
        Set-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_Enabled -Value 0 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name AppCaptureEnabled -Value 0 -Type DWord -Force -EA SilentlyContinue
        Write-Ok "Xbox Game DVR set to Off"
    }

    $relive = (Get-ItemProperty "HKCU:\Software\AMD\DVR" -Name DvrEnabled -EA SilentlyContinue).DvrEnabled
    if ($null -eq $relive) {
        Write-Info "AMD ReLive key not present"
    } elseif ($relive -eq 0) {
        Write-Ok "AMD ReLive: Off"
    } else {
        Write-Warn "AMD ReLive was On - disabling..."
        Set-ItemProperty "HKCU:\Software\AMD\DVR" -Name DvrEnabled -Value 0 -Type DWord -Force -EA SilentlyContinue
        Write-Ok "AMD ReLive set to Off"
    }

    try {
        $wu = Get-Service wuauserv -EA SilentlyContinue
        $bits = Get-Service bits -EA SilentlyContinue
        if ($wu -and $wu.Status -ne 'Running') {
            Write-Warn "Windows Update service was stopped - starting it"
            Start-Service wuauserv -EA SilentlyContinue
        } else {
            Write-Ok "Windows Update service: Running"
        }
        if ($bits -and $bits.Status -ne 'Running') {
            Write-Warn "BITS service was stopped - starting it"
            Start-Service bits -EA SilentlyContinue
        }
    } catch { }

    if (Test-RebootPending) {
        Write-Warn "A RESTART is pending - reboot when convenient (this is normal after updates)"
    } else {
        Write-Ok "No pending restart detected"
    }
}

function Invoke-Repair {
    Write-Step "Windows Repair (DISM + SFC)"
    Write-Info "This can take 10-30+ minutes. Do not close the window."

    try {
        Write-Info "DISM /RestoreHealth starting..."
        $dismLog = Join-Path (Split-Path $Script:LogFile) "dism_$(Get-Date -Format 'HHmmss').log"
        $p = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online","/Cleanup-Image","/RestoreHealth","/LogPath:$dismLog" -PassThru -NoNewWindow
        $spin = @('|','/','-','\'); $i = 0
        while (-not $p.HasExited) {
            $sec = [int]((Get-Date) - $p.StartTime).TotalSeconds
            Write-Host -NoNewline ("`r  [{0}] DISM running... {1}s   " -f $spin[$i % 4], $sec) -ForegroundColor DarkYellow
            Set-UiStatusText -Text ("[{0}] DISM running... {1}s" -f $spin[$i % 4], $sec)
            Pump-Ui
            Start-Sleep -Milliseconds 400
            $i++
        }
        Write-Host ""
        $null = $p.WaitForExit(1000)
        $code = $p.ExitCode
        $logText = ""
        if (Test-Path $dismLog) { $logText = Get-Content $dismLog -Raw -EA SilentlyContinue }
        $looksClean = ($logText -match "Ending Dism\.exe session") -and ($logText -notmatch ", Error\s+")
        if (($null -eq $code -or $code -eq 0) -or $looksClean) {
            Write-Ok "DISM completed successfully"
        } else {
            Write-Warn "DISM exit code $code - see $dismLog"
        }
    } catch {
        Write-Fail "DISM failed: $($_.Exception.Message)"
    }

    try {
        Write-Info "SFC /scannow starting..."
        $p = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -PassThru -NoNewWindow
        $spin = @('|','/','-','\'); $i = 0
        while (-not $p.HasExited) {
            $sec = [int]((Get-Date) - $p.StartTime).TotalSeconds
            Write-Host -NoNewline ("`r  [{0}] SFC running... {1}s   " -f $spin[$i % 4], $sec) -ForegroundColor DarkYellow
            Set-UiStatusText -Text ("[{0}] SFC running... {1}s" -f $spin[$i % 4], $sec)
            Pump-Ui
            Start-Sleep -Milliseconds 400
            $i++
        }
        Write-Host ""
        $null = $p.WaitForExit(1000)
        $code = $p.ExitCode
        if ($null -eq $code -or $code -eq 0) {
            Write-Ok "SFC finished successfully"
        } else {
            Write-Ok "SFC finished (exit $code) - see CBS.log if issues persist"
        }
    } catch {
        Write-Fail "SFC failed: $($_.Exception.Message)"
    }
}

function Get-RunSummaryText {
    $Script:EndFree = Get-CFreeGB
    $gained = [math]::Round($Script:EndFree - $Script:StartFree, 1)
    $elapsed = Get-Elapsed
    $lines = @(
        "Time elapsed  : $elapsed",
        "C: free before: $($Script:StartFree) GB",
        "C: free after : $($Script:EndFree) GB",
        "Space change  : $gained GB",
        "Log file      : $($Script:LogFile)",
        ""
    )
    foreach ($line in $Script:Report) { $lines += $line }
    return ($lines -join "`r`n")
}

function Invoke-MaintenanceRun {
    $Script:Report.Clear()
    $Script:RunStart = Get-Date
    Init-Log
    Build-StepPlan
    $Script:StartFree = Get-CFreeGB

    Write-Info "C: free space before: $($Script:StartFree) GB"
    Write-Log "Free before: $($Script:StartFree) GB"
    Write-Info ("Plan: " + ($Script:StepNames -join " > "))

    if ($Script:DoRestorePoint) { New-MaintenanceRestorePoint }
    if ($Script:DoCleanup) {
        Invoke-TempCleanup
        Invoke-BrowserCacheCleanup
        Invoke-RecycleAndCleanMgr
    }
    if ($Script:DoShaderCleanup) { Invoke-ShaderCacheCleanup }
    if ($Script:DoWinUpdate) { Invoke-WindowsUpdate }
    if ($Script:DoWinget) { Invoke-WingetUpdates }
    if ($Script:DoAmd) { Invoke-AmdOpen }
    if ($Script:DoRepair) { Invoke-Repair }
    if ($Script:DoGamingOptimize) {
        if (Get-Command Invoke-GamingOptimize -EA SilentlyContinue) {
            Invoke-GamingOptimize
        }
    }

    Invoke-GamingChecks

    $Script:CurrentStep = $Script:TotalSteps
    Update-UiProgress -Label "DONE"
    $summary = Get-RunSummaryText
    Write-Host ""
    Write-Host $summary
    Append-UiLog ""
    Append-UiLog "======== DONE ========" "Green"
    Append-UiLog $summary "Cyan"
    Write-Log "DONE"
    Write-Log $summary
    Show-RebootRecommendedDialog
    return $summary
}
