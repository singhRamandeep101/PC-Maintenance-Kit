#Requires -Version 5.1

$Script:Report = [System.Collections.Generic.List[string]]::new()
$Script:LogFile = $null
$Script:StartFree = 0
$Script:EndFree = 0
$Script:DoCleanup = $true
$Script:DoUpdates = $true
$Script:DoRepair = $false
$Script:DoRestorePoint = $true
$Script:DoAmd = $true
$Script:TotalSteps = 0
$Script:CurrentStep = 0
$Script:RunStart = Get-Date
$Script:StepNames = [System.Collections.Generic.List[string]]::new()
$Script:TempOlderThanDays = 2
$Script:Ui = $null
$Script:CancelRequested = $false

function Pump-Ui {
    if ($Script:Ui -and $Script:Ui.Form -and -not $Script:Ui.Form.IsDisposed) {
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Ensure-Admin {
    param([string]$RelaunchArgs = "")
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]::new($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($RelaunchArgs) { $arg += " $RelaunchArgs" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $arg
        exit
    }
}

function Init-Log {
    $dir = Join-Path $env:USERPROFILE "Desktop\PC-Maintenance-Logs"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $Script:LogFile = Join-Path $dir "maintenance_$stamp.log"
    "PC Maintenance v4 started: $(Get-Date)" | Out-File $Script:LogFile -Encoding UTF8
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
    if ($Script:TotalSteps -le 0) { return }
    $pct = [math]::Min(100, [math]::Round(($Script:CurrentStep / $Script:TotalSteps) * 100))
    if ($Script:Ui -and $Script:Ui.Progress) {
        $Script:Ui.Progress.Value = [math]::Min(100, [int]$pct)
        if ($Script:Ui.Status) {
            $Script:Ui.Status.Text = "Step $($Script:CurrentStep)/$($Script:TotalSteps)  $(Get-Elapsed)  $Label"
        }
    }
    $width = 30
    $filled = [math]::Round(($pct / 100) * $width)
    $bar = ("#" * $filled) + ("-" * ($width - $filled))
    try {
        $host.UI.RawUI.WindowTitle = "PC Maintenance  [$bar] $pct%  $($Script:CurrentStep)/$($Script:TotalSteps)  $(Get-Elapsed)  $Label"
    } catch { }
    Pump-Ui
}

function Append-UiLog {
    param([string]$msg, [string]$ColorName = "White")
    if (-not ($Script:Ui -and $Script:Ui.Log)) { return }
    $box = $Script:Ui.Log
    $color = switch ($ColorName) {
        'Green'  { [System.Drawing.Color]::FromArgb(80, 200, 120) }
        'Yellow' { [System.Drawing.Color]::FromArgb(230, 180, 60) }
        'Red'    { [System.Drawing.Color]::FromArgb(230, 90, 90) }
        'Cyan'   { [System.Drawing.Color]::FromArgb(80, 190, 220) }
        'Gray'   { [System.Drawing.Color]::FromArgb(140, 150, 160) }
        default  { [System.Drawing.Color]::FromArgb(220, 225, 230) }
    }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $color
    $box.AppendText("$msg`r`n")
    $box.SelectionStart = $box.TextLength
    $box.ScrollToCaret()
    Pump-Ui
}

function Write-Step([string]$msg) {
    $Script:CurrentStep++
    Write-Host ""
    Write-Host "=== [$($Script:CurrentStep)/$($Script:TotalSteps)] $msg ===" -ForegroundColor Cyan
    Update-UiProgress -Label $msg
    Append-UiLog "=== [$($Script:CurrentStep)/$($Script:TotalSteps)] $msg ===" "Cyan"
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
        if ($Script:Ui -and $Script:Ui.Status) {
            $Script:Ui.Status.Text = "[$ch] $Activity... ${sec}s / ${TimeoutSec}s"
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
            $Script:DoCleanup=$true; $Script:DoUpdates=$true; $Script:DoRepair=$false
            $Script:DoRestorePoint=$true; $Script:DoAmd=$true
        }
        'CleanupOnly' {
            $Script:DoCleanup=$true; $Script:DoUpdates=$false; $Script:DoRepair=$false
            $Script:DoRestorePoint=$false; $Script:DoAmd=$false
        }
        'UpdatesOnly' {
            $Script:DoCleanup=$false; $Script:DoUpdates=$true; $Script:DoRepair=$false
            $Script:DoRestorePoint=$true; $Script:DoAmd=$true
        }
        'Repair' {
            $Script:DoCleanup=$false; $Script:DoUpdates=$false; $Script:DoRepair=$true
            $Script:DoRestorePoint=$true; $Script:DoAmd=$false
        }
        'FullRepair' {
            $Script:DoCleanup=$true; $Script:DoUpdates=$true; $Script:DoRepair=$true
            $Script:DoRestorePoint=$true; $Script:DoAmd=$true
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
    if ($Script:DoUpdates) {
        [void]$Script:StepNames.Add("Windows Update")
        [void]$Script:StepNames.Add("winget upgrades")
    }
    if ($Script:DoAmd) { [void]$Script:StepNames.Add("AMD Adrenalin") }
    if ($Script:DoRepair) { [void]$Script:StepNames.Add("DISM + SFC repair") }
    [void]$Script:StepNames.Add("Health checks")
    $Script:TotalSteps = $Script:StepNames.Count
    $Script:CurrentStep = 0
}

function New-MaintenanceRestorePoint {
    Write-Step "Creating System Restore Point"
    Write-Info "This usually takes 10-60 seconds..."
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "PC Maintenance $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Ok "Restore point created"
    } catch {
        Write-Warn "Restore point skipped: $($_.Exception.Message)"
    }
}

function Remove-OldFilesInPath {
    param([string]$Path, [int]$OlderThanDays, [switch]$DeleteFoldersToo)
    if (-not (Test-Path $Path)) { return 0 }
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $freed = 0L
    Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            try { $freed += $_.Length; Remove-Item $_.FullName -Force -ErrorAction Stop } catch { }
            Pump-Ui
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
        Write-Info "Clearing Windows Update download cache..."
        $do = "C:\Windows\SoftwareDistribution\Download"
        if (Test-Path $do) {
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            Stop-Service bits -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $before = (Get-ChildItem $do -Recurse -Force -File -EA SilentlyContinue |
                Measure-Object Length -Sum -EA SilentlyContinue).Sum
            if (-not $before) { $before = 0 }
            Get-ChildItem $do -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue
            $total += $before
            $job = Start-Job { Start-Service bits -EA SilentlyContinue; Start-Service wuauserv -EA SilentlyContinue }
            $null = Wait-Job $job -Timeout 15
            Remove-Job $job -Force -EA SilentlyContinue
            Write-Ok ("Update download cache: {0:N0} MB" -f ($before / 1MB))
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
    Write-Info "Scan can take 1-5 minutes"
    try {
        $have = Get-Module -ListAvailable PSWindowsUpdate -EA SilentlyContinue
        if (-not $have) {
            Write-Info "Installing PSWindowsUpdate module (one-time)..."
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -EA SilentlyContinue | Out-Null
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -EA SilentlyContinue
                Install-Module PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers -EA Stop
                Write-Ok "PSWindowsUpdate installed"
            } catch {
                Write-Warn "Module install failed - using UsoClient fallback"
                UsoClient StartInteractiveScan 2>$null
                Write-Ok "Windows Update scan started (check Settings > Windows Update)"
                return
            }
        }

        Import-Module PSWindowsUpdate -EA SilentlyContinue
        Write-Info "Scanning for updates..."
        $updates = @(Get-WindowsUpdate -MicrosoftUpdate -EA SilentlyContinue)
        if ($updates.Count -gt 0) {
            Write-Info "Found $($updates.Count) update(s). Installing..."
            $n = 0
            foreach ($u in $updates) {
                $n++
                Write-Info ("Update {0}/{1}: {2}" -f $n, $updates.Count, $u.Title)
            }
            Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -EA SilentlyContinue | Out-Null
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
        $null = Get-Command winget -EA Stop
        Write-Info "Scanning for app upgrades..."
        $out = & winget upgrade --all --accept-package-agreements --accept-source-agreements --disable-interactivity --include-unknown 2>&1 | Out-String
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

    $reboot = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $reboot = $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $reboot = $true }
    if ($reboot) { Write-Warn "A RESTART is pending" } else { Write-Ok "No pending restart detected" }
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
            if ($Script:Ui -and $Script:Ui.Status) {
                $Script:Ui.Status.Text = "[$($spin[$i % 4])] DISM running... ${sec}s"
            }
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
            if ($Script:Ui -and $Script:Ui.Status) {
                $Script:Ui.Status.Text = "[$($spin[$i % 4])] SFC running... ${sec}s"
            }
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
    if ($Script:DoUpdates) {
        Invoke-WindowsUpdate
        Invoke-WingetUpdates
    }
    if ($Script:DoAmd) { Invoke-AmdOpen }
    if ($Script:DoRepair) { Invoke-Repair }

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
    return $summary
}
