#Requires -Version 5.1
$Script:Report = [System.Collections.Generic.List[string]]::new()
$Script:StartFree = 0
$Script:EndFree = 0
$Script:DoCleanup = $true
$Script:DoWinUpdate = $false
$Script:DoWinget = $false
$Script:DoRepair = $false
$Script:DoRestorePoint = $true
$Script:DoAmd = $false
$Script:DoShaderCleanup = $true
$Script:DoGamingOptimize = $true
$Script:DoWuCacheWipe = $false
$Script:TotalSteps = 0
$Script:CurrentStep = 0
$Script:RunStart = Get-Date
$Script:StepNames = [System.Collections.Generic.List[string]]::new()
$Script:TempOlderThanDays = 2
$Script:Ui = $null
$Script:LastPumpUtc = [datetime]::MinValue
$Script:LastProgressPct = 0
$Script:CancelRequested = $false
$Script:TrackedProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$Script:UiShare = $null
$Script:BgPowerShell = $null
function Reset-MaintenanceFlags {
    # Safe weekly defaults - callers override what they need
    $Script:DoCleanup = $true
    $Script:DoWinUpdate = $false
    $Script:DoWinget = $false
    $Script:DoRepair = $false
    $Script:DoRestorePoint = $true
    $Script:DoAmd = $false
    $Script:DoShaderCleanup = $true
    $Script:DoGamingOptimize = $true
    $Script:DoWuCacheWipe = $false
    $Script:TempOlderThanDays = 2
}

function Test-CancelRequested {
    if ($Script:UiShare -and $null -ne $Script:UiShare['CancelRequested']) {
        return [bool]$Script:UiShare['CancelRequested']
    }
    return [bool]$Script:CancelRequested
}

function Request-MaintenanceCancel {
    $Script:CancelRequested = $true
    if ($Script:UiShare) { $Script:UiShare['CancelRequested'] = $true }
    Write-Warn "Cancel requested - stopping after current step..."
    foreach ($p in @($Script:TrackedProcesses)) {
        try {
            if ($p -and -not $p.HasExited) { $p.Kill() }
        } catch { }
    }
    if ($Script:BgPowerShell) {
        try { $Script:BgPowerShell.Stop() } catch { }
    }
}

function Assert-NotCancelled {
    if (Test-CancelRequested) {
        throw "Cancelled by user."
    }
}

function Register-TrackedProcess {
    param([System.Diagnostics.Process]$Process)
    if ($Process) {
        try { [void]$Script:TrackedProcesses.Add($Process) } catch { }
    }
}

function Clear-TrackedProcesses {
    try { $Script:TrackedProcesses.Clear() } catch { }
}

function Enqueue-UiEvent {
    param([hashtable]$UiEvent)
    if ($Script:UiShare -and $Script:UiShare.Queue) {
        $Script:UiShare.Queue.Enqueue($UiEvent)
        return $true
    }
    return $false
}

$Script:UiModalDepth = 0

function Invoke-WithUiModal {
    param([scriptblock]$Action)
    if (-not $Action) { return $null }
    $Script:UiModalDepth = [int]$Script:UiModalDepth + 1
    try {
        return & $Action
    } finally {
        $Script:UiModalDepth = [math]::Max(0, [int]$Script:UiModalDepth - 1)
    }
}

function Show-UiMessageBox {
    param(
        [string]$Text,
        [string]$Caption = "PC Maintenance Kit",
        $Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
    } catch { }
    return Invoke-WithUiModal {
        [System.Windows.Forms.MessageBox]::Show($Text, $Caption, $Buttons, $Icon)
    }
}

function Pump-Ui {
    if ([int]$Script:UiModalDepth -gt 0) { return }
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
    if (Enqueue-UiEvent @{ Type = 'Progress'; Value = $Value }) { return }
    $pct = [math]::Max(0, [math]::Min(100, $Value))
    $Script:LastProgressPct = $pct
    $fill = Get-UiControl ProgressFill
    $track = Get-UiControl ProgressTrack
    if ($fill -and $track) {
        $w = [math]::Max(0, [int](($track.ClientSize.Width * $pct) / 100.0))
        # Full invalidate: WinForms only paints newly exposed strips on resize,
        # which stacks old gradient segments into stripes.
        if ($fill.Width -ne $w) {
            $fill.Width = $w
            $fill.Invalidate()
        }
    }
}

function Set-UiStatusText([string]$Text) {
    if (Enqueue-UiEvent @{ Type = 'Status'; Text = $Text }) { return }
    $lbl = Get-UiControl Status
    if ($lbl) { $lbl.Text = $Text }
}

function Invoke-WithUiWait {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Activity = "Working",
        [int]$TimeoutSec = 900,
        [object[]]$ArgumentList = @(),
        [switch]$Sta
    )
    Assert-NotCancelled
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    if ($Sta) {
        $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    }
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $Script:BgPowerShell = $ps
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
            if (Test-CancelRequested) {
                try { $ps.Stop() } catch { }
                Write-Warn "$Activity cancelled"
                return $null
            }
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
        if (Test-CancelRequested) {
            Write-Warn "$Activity cancelled"
            return $null
        }
        $result = $ps.EndInvoke($handle)
        if ($ps.HadErrors) {
            foreach ($e in $ps.Streams.Error) {
                Write-Warn ("Background error: " + $e.ToString())
            }
        }
        return $result
    } finally {
        $Script:BgPowerShell = $null
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
    if (-not $ScriptPath -or -not (Test-PathSafe $ScriptPath)) {
        throw "Cannot elevate: script path not found."
    }

    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    # Hide console for Gui elevate; keep visible for Cli / one-shot modes
    $hideGui = ($RelaunchArgs -match '-Mode\s+Gui') -or ($RelaunchArgs -notmatch '-Mode\s+')
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

function Get-AppTempDirectory {
    $dir = Join-Path $env:TEMP "PC-Maintenance-Kit"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-Elapsed {
    $ts = (Get-Date) - $Script:RunStart
    if ($ts.TotalHours -ge 1) {
        return "{0:00}:{1:00}:{2:00}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds
    }
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
    $plain = ("Running: {0}  |  {1}/{2}  |  {3}" -f $Label, $Script:CurrentStep, $Script:TotalSteps, (Get-Elapsed))
    Set-UiStatusText -Text $plain
    if (Get-Command Update-GuiStatusBar -EA SilentlyContinue) {
        Update-GuiStatusBar -JobText $plain
    }
    try {
        $host.UI.RawUI.WindowTitle = "PC Maintenance Kit  $pct%  $($Script:CurrentStep)/$($Script:TotalSteps)  $(Get-Elapsed)"
    } catch { }
    Pump-Ui
}

function Get-UiLogColor {
    # Single source of truth - the GUI queue drains through here too
    param([string]$ColorName = "White")
    switch ($ColorName) {
        'Green'  { return [System.Drawing.Color]::FromArgb(52, 211, 153) }
        'Yellow' { return [System.Drawing.Color]::FromArgb(251, 191, 36) }
        'Red'    { return [System.Drawing.Color]::FromArgb(251, 113, 133) }
        'Cyan'   { return [System.Drawing.Color]::FromArgb(34, 211, 238) }
        'Gray'   { return [System.Drawing.Color]::FromArgb(120, 140, 175) }
        default  { return [System.Drawing.Color]::FromArgb(210, 222, 240) }
    }
}

function Append-UiLog {
    param([string]$msg, [string]$ColorName = "White")
    if (Enqueue-UiEvent @{ Type = 'Log'; Msg = $msg; Color = $ColorName }) { return }
    $box = Get-UiControl Log
    if (-not $box) { return }
    $color = Get-UiLogColor $ColorName
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
    Assert-NotCancelled
    $Script:CurrentStep++
    Write-Host ""
    Write-Host "=== [$($Script:CurrentStep)/$($Script:TotalSteps)] $msg ===" -ForegroundColor Cyan
    Update-UiProgress -Label $msg
    Append-UiLog (">> [{0}/{1}] {2}" -f $Script:CurrentStep, $Script:TotalSteps, $msg) "Cyan"
}

function Write-Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
    $Script:Report.Add("[OK] $msg") | Out-Null
    Append-UiLog "  [OK] $msg" "Green"
}

function Write-Warn([string]$msg) {
    Write-Host "  [!] $msg" -ForegroundColor Yellow
    $Script:Report.Add("[!] $msg") | Out-Null
    Append-UiLog "  [!] $msg" "Yellow"
}

function Write-Fail([string]$msg) {
    Write-Host "  [X] $msg" -ForegroundColor Red
    $Script:Report.Add("[X] $msg") | Out-Null
    Append-UiLog "  [X] $msg" "Red"
}

function Write-Info([string]$msg) {
    Write-Host "  ... $msg" -ForegroundColor DarkGray
    Append-UiLog "  ... $msg" "Gray"
}

function Get-CFreeGB {
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    if (-not $d -or $null -eq $d.FreeSpace) { return 0 }
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

function Apply-ModeFlags {
    param(
        [ValidateSet('Full','CleanupOnly','UpdatesOnly','Repair','FullRepair')]
        [string]$ModeName
    )
    switch ($ModeName) {
        'Full' {
            $Script:DoCleanup=$true; $Script:DoWinUpdate=$false; $Script:DoWinget=$false
            $Script:DoRepair=$false; $Script:DoRestorePoint=$true; $Script:DoAmd=$false
            $Script:DoShaderCleanup=$true; $Script:DoGamingOptimize=$true
            $Script:DoWuCacheWipe=$false
        }
        'CleanupOnly' {
            $Script:DoCleanup=$true; $Script:DoWinUpdate=$false; $Script:DoWinget=$false
            $Script:DoRepair=$false; $Script:DoRestorePoint=$false; $Script:DoAmd=$false
            $Script:DoShaderCleanup=$true; $Script:DoGamingOptimize=$false
            $Script:DoWuCacheWipe=$false
        }
        'UpdatesOnly' {
            $Script:DoCleanup=$false; $Script:DoWinUpdate=$true; $Script:DoWinget=$true
            $Script:DoRepair=$false; $Script:DoRestorePoint=$true; $Script:DoAmd=$true
            $Script:DoShaderCleanup=$false; $Script:DoGamingOptimize=$false
            $Script:DoWuCacheWipe=$false
        }
        'Repair' {
            $Script:DoCleanup=$false; $Script:DoWinUpdate=$false; $Script:DoWinget=$false
            $Script:DoRepair=$true; $Script:DoRestorePoint=$true; $Script:DoAmd=$false
            $Script:DoShaderCleanup=$false; $Script:DoGamingOptimize=$false
            $Script:DoWuCacheWipe=$false
        }
        'FullRepair' {
            $Script:DoCleanup=$true; $Script:DoWinUpdate=$true; $Script:DoWinget=$true
            $Script:DoRepair=$true; $Script:DoRestorePoint=$true; $Script:DoAmd=$true
            $Script:DoShaderCleanup=$true; $Script:DoGamingOptimize=$true
            $Script:DoWuCacheWipe=$false
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

function Get-ProtectedCleanupPaths {
    # Folders that must never be handed to a recursive delete, even by a future caller.
    $list = [System.Collections.Generic.List[string]]::new()
    $roots = @(
        $env:SystemDrive, $env:SystemRoot, $env:windir, $env:HOMEDRIVE,
        $env:USERPROFILE, $env:PUBLIC, $env:ProgramData,
        $env:ProgramFiles, ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA, $env:APPDATA,
        (Join-PathSafe $env:SystemRoot 'System32'),
        (Join-PathSafe $env:SystemRoot 'SysWOW64'),
        (Join-PathSafe $env:LOCALAPPDATA 'Programs'),
        (Join-PathSafe $env:USERPROFILE 'Desktop'),
        (Join-PathSafe $env:USERPROFILE 'Documents'),
        (Join-PathSafe $env:USERPROFILE 'Downloads'),
        (Join-PathSafe $env:USERPROFILE 'Pictures'),
        (Join-PathSafe $env:USERPROFILE 'Videos'),
        (Join-PathSafe $env:USERPROFILE 'Music'),
        (Join-PathSafe $env:USERPROFILE 'Saved Games'),
        (Join-PathSafe $env:SystemDrive '\Users')
    )
    foreach ($p in $roots) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        [void]$list.Add((([string]$p).TrimEnd('\', '/')).ToLowerInvariant())
    }
    return $list
}

function Test-SafeCleanupPath {
    # Structural guard for every recursive delete. Fails closed.
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    # "C:" is drive-relative and GetFullPath would expand it to the current
    # directory, so reject bare drive specs before they can look deep and safe.
    if ($Path.Trim() -match '^[A-Za-z]:$') { return $false }

    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $false }
    if ([string]::IsNullOrWhiteSpace($full)) { return $false }

    $norm = $full.TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($norm)) { return $false }
    $key = $norm.ToLowerInvariant()

    # Drive root (C:) or UNC share root (\\server\share)
    if ($key -match '^[a-z]:$') { return $false }
    if ($key -match '^\\\\[^\\]+\\[^\\]+$') { return $false }

    foreach ($protected in (Get-ProtectedCleanupPaths)) {
        if ($key -eq $protected) { return $false }
    }

    # Shallowest path we ever clean is C:\Windows\Temp - two segments below the root
    $segments = @($norm -split '[\\/]+' | Where-Object { $_ -and $_ -notmatch '^[A-Za-z]:$' })
    if ($segments.Count -lt 2) { return $false }

    return $true
}

function Assert-SafeCleanupPath {
    param([string]$Path, [string]$Operation = 'cleanup')
    if (Test-SafeCleanupPath -Path $Path) { return $true }
    $shown = if ([string]::IsNullOrWhiteSpace($Path)) { '<empty>' } else { $Path }
    Write-Warn ("Refused unsafe {0} path: {1}" -f $Operation, $shown)
    return $false
}

function Remove-OldFilesInPath {
    param([string]$Path, [int]$OlderThanDays, [switch]$DeleteFoldersToo)
    if (-not (Assert-SafeCleanupPath -Path $Path -Operation 'cleanup')) { return 0 }
    if (-not (Test-Path $Path)) { return 0 }
    Assert-NotCancelled
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $freed = 0L
    $n = 0
    Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            if (Test-CancelRequested) { return }
            try { $freed += $_.Length; Remove-Item $_.FullName -Force -ErrorAction Stop } catch { }
            $n++
            if (($n % 80) -eq 0) {
                Assert-NotCancelled
                Pump-UiThrottled
            }
        }
    if (Test-CancelRequested) { return $freed }
    if ($DeleteFoldersToo) {
        Get-ChildItem -Path $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            ForEach-Object {
                if (Test-CancelRequested) { return }
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
    # GPU shader caches are handled only by Invoke-ShaderCacheCleanup (checkbox-driven)
    $raw = @(
        $env:TEMP,
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows\Temp",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"
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
        if (-not $Script:DoWuCacheWipe) {
            Write-Info "Skipped Windows Update download-cache wipe (opt-in on Cleanup tab)"
        } elseif ($Script:DoWinUpdate) {
            Write-Info "Skipped Windows Update download-cache wipe (updates will run next)"
        } else {
            Write-Info "Clearing Windows Update download cache..."
            $do = Join-PathSafe $env:SystemRoot 'SoftwareDistribution\Download'
            if ($do -and (Assert-SafeCleanupPath -Path $do -Operation 'update cache wipe') -and (Test-Path $do)) {
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

function Get-ChromiumProfileCachePaths {
    param([string]$UserDataRoot)
    $list = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($UserDataRoot) -or -not (Test-PathSafe $UserDataRoot)) {
        return @()
    }

    # Shared GPU caches live under User Data (not inside a profile folder)
    foreach ($rootSub in @('ShaderCache', 'GrShaderCache', 'GraphiteDawnCache')) {
        $rp = Join-Path $UserDataRoot $rootSub
        if (Test-PathSafe $rp) { [void]$list.Add($rp) }
    }

    $skip = @{
        'Crashpad' = $true; 'ShaderCache' = $true; 'GrShaderCache' = $true; 'GraphiteDawnCache' = $true
        'BrowserMetrics' = $true; 'Safe Browsing' = $true; 'CertificateRevocation' = $true
        'Component Crx Cache' = $true; 'MEIPreload' = $true; 'OptimizationHints' = $true
        'OriginTrials' = $true; 'PKIMetadata' = $true; 'SSLErrorAssistant' = $true
        'Subresource Filter' = $true; 'TrustTokenKeyCommitments' = $true; 'hyphen-data' = $true
        'WidevineCdm' = $true; 'ZxcvbnData' = $true; 'Dictionaries' = $true
        'FileTypePolicies' = $true; 'Crowd Deny' = $true; 'AutofillStates' = $true
        'FirstPartySetsPreloaded' = $true; 'OpenCookieDatabase' = $true
        'PrivacySandboxAttestationsPreloaded' = $true; 'segmentation_platform' = $true
        'AmountExtractionHeuristicRegexes' = $true; 'TOS' = $true
    }

    $profiles = @(Get-ChildItem -LiteralPath $UserDataRoot -Directory -EA SilentlyContinue | Where-Object {
        if ($skip.ContainsKey($_.Name)) { return $false }
        if ($_.Name -eq 'Default' -or $_.Name -eq 'Guest Profile' -or $_.Name -like 'Profile *' -or $_.Name -like 'Person *') {
            return $true
        }
        # Heuristic: Chromium profile dirs usually have Preferences and/or a Cache folder
        return (Test-PathSafe (Join-Path $_.FullName 'Preferences')) -or (Test-PathSafe (Join-Path $_.FullName 'Cache'))
    })

    foreach ($profileDir in $profiles) {
        foreach ($sub in @('Cache', 'Code Cache', 'GPUCache', 'ShaderCache')) {
            $p = Join-Path $profileDir.FullName $sub
            if (Test-PathSafe $p) { [void]$list.Add($p) }
        }
    }
    return @($list)
}

function Get-BrowserCachePaths {
    $map = [ordered]@{}
    $chromium = [ordered]@{
        Brave  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
        Chrome = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        Edge   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    }
    foreach ($name in $chromium.Keys) {
        $paths = @(Get-ChromiumProfileCachePaths -UserDataRoot $chromium[$name])
        if ($paths.Count -gt 0) { $map[$name] = $paths }
    }
    $ffRoot = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-PathSafe $ffRoot) {
        $ff = [System.Collections.Generic.List[string]]::new()
        Get-ChildItem -LiteralPath $ffRoot -Directory -EA SilentlyContinue | ForEach-Object {
            $cache = Join-Path $_.FullName 'cache2'
            if (Test-PathSafe $cache) { [void]$ff.Add($cache) }
        }
        if ($ff.Count -gt 0) { $map['Firefox'] = @($ff) }
    }
    return $map
}

function Invoke-BrowserCacheCleanup {
    Write-Step "Cleaning browser caches (all profiles)"
    Write-Info "Close browsers for best results (locked files are skipped)"
    $total = 0L
    $browserPaths = Get-BrowserCachePaths

    foreach ($browser in $browserPaths.Keys) {
        Write-Info "Checking $browser..."
        $freedBrowser = 0L
        foreach ($p in $browserPaths[$browser]) {
            if (-not (Test-PathSafe $p)) { continue }
            $freedBrowser += Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
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

function Get-WindowsUpdateTitlesFromAsync {
    param($Result)
    $titles = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Result) {
        return @{ Status = "ERR"; Titles = @(); Message = "No result" }
    }

    $payload = $null
    foreach ($item in @($Result)) {
        if ($null -eq $item) { continue }
        if ($item -is [System.Management.Automation.PSCustomObject] -or $item -is [hashtable]) {
            $payload = $item
        }
    }
    if ($null -eq $payload) {
        $payload = @($Result) | Select-Object -Last 1
    }

    $status = $null
    try { $status = [string]$payload.Status } catch { $status = $null }
    if ($status -eq "ERR") {
        $msg = ""
        try { $msg = [string]$payload.Message } catch { }
        return @{ Status = "ERR"; Titles = @(); Message = $msg }
    }
    if ($status -eq "OK") {
        $rawTitles = @()
        try { $rawTitles = @($payload.Titles) } catch { $rawTitles = @() }
        foreach ($t in $rawTitles) {
            if ($null -eq $t) { continue }
            # Never foreach a [string] as IEnumerable - that yields characters
            if ($t -is [string]) {
                if ($t.Trim()) { [void]$titles.Add($t.Trim()) }
                continue
            }
            $s = "$t".Trim()
            if ($s) { [void]$titles.Add($s) }
        }
        return @{ Status = "OK"; Titles = @($titles | Select-Object -Unique); Message = $null }
    }

    return @{ Status = "ERR"; Titles = @(); Message = "Unexpected Windows Update scan result" }
}

function Invoke-WindowsUpdate {
    Write-Step "Windows Updates"
    Write-Info "Scan runs in the background so the window stays responsive"
    try {
        $have = Get-Module -ListAvailable PSWindowsUpdate -EA SilentlyContinue
        if (-not $have) {
            Write-Info "Installing PSWindowsUpdate module (one-time)..."
            $installed = Invoke-WithUiWait -Activity "Installing update module" -TimeoutSec 300 -Sta -ScriptBlock {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -EA SilentlyContinue | Out-Null
                    $prevPolicy = 'Untrusted'
                    try {
                        $repo = Get-PSRepository -Name PSGallery -EA SilentlyContinue
                        if ($repo -and $repo.InstallationPolicy) {
                            $prevPolicy = [string]$repo.InstallationPolicy
                        }
                    } catch { }
                    try {
                        # Temporarily trust PSGallery for a non-interactive install, then restore.
                        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -EA SilentlyContinue
                        Install-Module PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers -EA Stop
                    } finally {
                        if ($prevPolicy -ne 'Trusted') {
                            Set-PSRepository -Name PSGallery -InstallationPolicy $prevPolicy -EA SilentlyContinue
                        }
                    }
                    "OK"
                } catch {
                    "ERR:" + $_.Exception.Message
                }
            }
            $instText = Get-AsyncResultText $installed
            if ($instText -ne "OK") {
                Write-Warn "Module install failed - cannot install updates from this app"
                Start-WindowsUpdateFallbackScan
                return
            }
            Write-Ok "PSWindowsUpdate installed"
        }

        Write-Info "Scanning Windows Update (can take several minutes on first run)..."
        # STA + Windows Update only (no -MicrosoftUpdate) - Microsoft Update catalog often hangs/timeouts
        $scan = Invoke-WithUiWait -Activity "Scanning Windows Update" -TimeoutSec 1200 -Sta -ScriptBlock {
            try {
                Import-Module PSWindowsUpdate -Force -EA Stop
                $list = @(Get-WindowsUpdate -WindowsUpdate -ErrorAction Stop)
                $titles = [System.Collections.Generic.List[string]]::new()
                foreach ($u in $list) {
                    if ($null -eq $u) { continue }
                    if ($u.Title) { [void]$titles.Add([string]$u.Title) }
                    elseif ($u.KB) { [void]$titles.Add("KB$($u.KB)") }
                    else { [void]$titles.Add([string]$u.ToString()) }
                }
                ,[pscustomobject]@{ Status = "OK"; Titles = @($titles); Message = $null }
            } catch {
                ,[pscustomobject]@{ Status = "ERR"; Titles = @(); Message = $_.Exception.Message }
            }
        }

        if ($null -eq $scan) {
            Write-Warn "Windows Update scan timed out after 20 min - opening Settings (scan only, nothing installed)"
            Start-WindowsUpdateFallbackScan
            return
        }

        $parsed = Get-WindowsUpdateTitlesFromAsync $scan
        if ($parsed.Status -eq "ERR") {
            Write-Fail ("Windows Update scan failed: {0}" -f $(if ($parsed.Message) { $parsed.Message } else { "unknown error" }))
            Start-WindowsUpdateFallbackScan
            return
        }

        $titles = @($parsed.Titles)
        if ($titles.Count -gt 0) {
            Write-Info ("Found {0} update(s). Installing..." -f $titles.Count)
            $n = 0
            foreach ($t in $titles) {
                $n++
                Write-Info ("Update {0}/{1}: {2}" -f $n, $titles.Count, $t)
            }
            $install = Invoke-WithUiWait -Activity "Installing Windows Updates" -TimeoutSec 3600 -Sta -ScriptBlock {
                try {
                    # Raw WIA COM API instead of PSWindowsUpdate install: works in non-interactive
                    # hosts (hidden window), accepts EULAs up front, and skips updates whose
                    # installer would pop a user-input dialog (the cause of "command that prompts
                    # the user failed" errors).
                    $session = New-Object -ComObject Microsoft.Update.Session
                    $searcher = $session.CreateUpdateSearcher()
                    $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
                    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
                    $skippedInput = New-Object System.Collections.Generic.List[string]
                    foreach ($u in @($result.Updates)) {
                        if ($null -eq $u) { continue }
                        try { if (-not $u.EulaAccepted) { $u.AcceptEula() } } catch { }
                        $needsInput = $false
                        try { if ($u.InstallationBehavior.CanRequestUserInput) { $needsInput = $true } } catch { }
                        if ($needsInput) {
                            [void]$skippedInput.Add([string]$u.Title)
                            continue
                        }
                        [void]$coll.Add($u)
                    }
                    $notes = New-Object System.Collections.Generic.List[string]
                    if ($skippedInput.Count -gt 0) {
                        [void]$notes.Add(("SKIPPED(user input): {0}" -f (($skippedInput | Select-Object -First 3) -join "; ")))
                    }
                    if ($coll.Count -eq 0) {
                        if ($skippedInput.Count -gt 0) {
                            "OK|installed=0|failed=0|reboot=0|" + (($notes | Select-Object -First 5) -join "; ")
                        } else {
                            "EMPTY"
                        }
                        return
                    }
                    $downloader = $session.CreateUpdateDownloader()
                    $downloader.Updates = $coll
                    $dl = $downloader.Download()
                    if ([int]$dl.ResultCode -eq 4) {
                        throw ("Download failed (HResult {0})" -f $dl.HResult)
                    }
                    $installer = $session.CreateUpdateInstaller()
                    $installer.Updates = $coll
                    $res = $installer.Install()
                    $ok = 0; $fail = 0; $reboot = 0
                    for ($i = 0; $i -lt $coll.Count; $i++) {
                        $r = $res.GetUpdateResult($i)
                        $title = [string]$coll.Item($i).Title
                        $code = 0
                        try { $code = [int]$r.ResultCode } catch { }
                        $needReboot = $false
                        try { if ($r.RebootRequired) { $needReboot = $true; $reboot++ } } catch { }
                        switch ($code) {
                            2 { $ok++; if ($needReboot) { [void]$notes.Add(("REBOOT: {0}" -f $title)) } }
                            3 { $ok++; [void]$notes.Add(("PARTIAL: {0}" -f $title)) }
                            default {
                                $fail++
                                [void]$notes.Add(("FAIL: {0} (code {1})" -f $title, $code))
                            }
                        }
                    }
                    if ($fail -gt 0 -and $ok -eq 0) {
                        "ERR:" + (($notes | Select-Object -First 3) -join "; ")
                    } else {
                        "OK|installed=$ok|failed=$fail|reboot=$reboot|" + (($notes | Select-Object -First 5) -join "; ")
                    }
                } catch {
                    "ERR:" + $_.Exception.Message
                }
            }
            if ($null -eq $install) {
                Write-Warn "Install timed out - open Settings > Windows Update to finish"
                Start-WindowsUpdateFallbackScan
                return
            }
            $instText = Get-AsyncResultText $install
            if ($instText -eq "EMPTY") {
                Write-Warn "Windows Update install returned no results - check Settings > Windows Update"
            } elseif ($instText -like "ERR:*") {
                Write-Fail ("Windows Update install failed: {0}" -f $instText.Substring(4))
                Start-WindowsUpdateFallbackScan
                return
            } elseif ($instText -like "OK|*") {
                Write-Ok "Windows Updates install pass finished"
                if ($instText -match 'reboot=([1-9]\d*)') {
                    Write-Warn "At least one update needs a reboot before it fully applies"
                }
                if ($instText -match 'failed=([1-9]\d*)') {
                    Write-Warn "Some updates reported failure"
                }
            } elseif ($instText -ne "OK") {
                $errMsg = if ($instText -like "ERR:*") { $instText.Substring(4) } else { $instText }
                Write-Fail ("Windows Update install failed: {0}" -f $(if ($errMsg) { $errMsg } else { "unknown error" }))
                Start-WindowsUpdateFallbackScan
                return
            } else {
                Write-Ok "Windows Updates install pass finished (reboot may be required)"
            }

            # Re-scan so we do not claim success while Settings still lists updates
            Write-Info "Re-scanning to verify remaining updates..."
            $verify = Invoke-WithUiWait -Activity "Verifying Windows Update" -TimeoutSec 900 -Sta -ScriptBlock {
                try {
                    Import-Module PSWindowsUpdate -Force -EA Stop
                    $list = @(Get-WindowsUpdate -WindowsUpdate -ErrorAction Stop)
                    $titles = [System.Collections.Generic.List[string]]::new()
                    foreach ($u in $list) {
                        if ($null -eq $u) { continue }
                        if ($u.Title) { [void]$titles.Add([string]$u.Title) }
                        elseif ($u.KB) { [void]$titles.Add("KB$($u.KB)") }
                        else { [void]$titles.Add([string]$u.ToString()) }
                    }
                    ,[pscustomobject]@{ Status = "OK"; Titles = @($titles); Message = $null }
                } catch {
                    ,[pscustomobject]@{ Status = "ERR"; Titles = @(); Message = $_.Exception.Message }
                }
            }
            if ($null -ne $verify) {
                $vParsed = Get-WindowsUpdateTitlesFromAsync $verify
                if ($vParsed.Status -eq "OK" -and @($vParsed.Titles).Count -gt 0) {
                    Write-Warn ("{0} update(s) still pending - reboot, then check Settings > Windows Update" -f @($vParsed.Titles).Count)
                    foreach ($t in @($vParsed.Titles | Select-Object -First 8)) {
                        Write-Info ("  still pending: {0}" -f $t)
                    }
                } elseif ($vParsed.Status -eq "OK") {
                    Write-Ok "Windows is up to date"
                } else {
                    Write-Warn "Could not verify remaining updates - check Settings > Windows Update"
                }
            } else {
                Write-Warn "Verify scan timed out - check Settings > Windows Update (reboot may still be needed)"
            }
        } else {
            Write-Ok "Windows is up to date"
        }
    } catch {
        Write-Fail "Windows Update: $($_.Exception.Message)"
        Start-WindowsUpdateFallbackScan
    }
}

function Start-WindowsUpdateFallbackScan {
    # Scan / open Settings only - does NOT install updates. Never report this as success.
    Write-Warn "Fallback cannot install updates here - opening Windows Update so you can finish manually"
    $started = $false
    try {
        $p = Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartInteractiveScan" -Wait -PassThru -WindowStyle Hidden -EA Stop
        if ($p.ExitCode -eq 0) { $started = $true }
    } catch { }
    try {
        Start-Process "ms-settings:windowsupdate" -EA SilentlyContinue
        $started = $true
    } catch { }
    if ($started) {
        Write-Warn "Windows Update Settings opened - install any listed updates there"
    } else {
        Write-Fail "Could not start Windows Update fallback"
    }
}

function Invoke-WingetUpdates {
    Write-Step "Upgrading apps (winget)"
    # Packages that winget repeatedly "upgrades" (unknown versions / self-updaters) - skip them
    $wingetSkipIds = @(
        "Roblox.Roblox",
        "Discord.Discord",
        "EpicGames.EpicGamesLauncher",
        "Valve.Steam"
    )
    try {
        Assert-NotCancelled
        $winget = (Get-Command winget -EA Stop).Source
        Write-Info "Listing available upgrades (winget source only - faster)..."
        # No --include-unknown: that flag makes apps like Roblox look upgradeable forever
        # --source winget skips slow msstore queries on every list/upgrade
        $listObj = Invoke-WithUiWait -Activity "winget list upgrades" -TimeoutSec 300 -ArgumentList @($winget) -ScriptBlock {
            param([string]$WingetPath)
            $text = & $WingetPath upgrade --source winget --disable-interactivity --accept-source-agreements 2>&1 | Out-String
            [pscustomobject]@{ Output = $text; ExitCode = $LASTEXITCODE }
        }
        if ($null -eq $listObj) {
            Write-Warn "winget list timed out or cancelled"
            return
        }
        $listPayload = @($listObj) | Select-Object -Last 1
        $listOut = ""
        try { $listOut = [string]$listPayload.Output } catch { $listOut = Get-AsyncResultText $listObj }
        if ([string]::IsNullOrWhiteSpace($listOut)) {
            Write-Warn "winget list returned no output"
            return
        }

        if ($listOut -match "No newer package versions" -or
            ($listOut -match "No installed package found matching input criteria" -and $listOut -notmatch '\dupgrades?\s+available')) {
            Write-Ok "winget apps are up to date"
            return
        }

        $packageLines = @()
        $packageIds = [System.Collections.Generic.List[string]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()
        $idCol = -1
        $verCol = -1
        foreach ($line in ($listOut -split "`r?`n")) {
            if ($line -match '^\s*$') { continue }
            if ($line -match '^Name\s+Id\s+Version') {
                $idCol = $line.IndexOf('Id')
                $verCol = $line.IndexOf('Version')
                continue
            }
            if ($line -match '^-+' -or $line -match '^\s*\d+\s+upgrades? available' -or $line -match '\d\s+upgrades?\s+available' -or $line -match '^\s*\d+\s+package' -or $line -match 'The following packages' -or $line -match 'require explicit targeting' -or $line -match 'have an upgrade available' -or $line -match 'No installed package found' -or $line -match 'No newer package versions' -or $line -match 'version numbers that cannot be determined') {
                continue
            }

            $id = $null
            # Fixed-width columns from header (handles Node.js names and msstore Ids)
            if ($idCol -ge 0 -and $verCol -gt $idCol -and $line.Length -gt $idCol) {
                $end = [Math]::Min($verCol, $line.Length)
                $id = $line.Substring($idCol, $end - $idCol).Trim()
                # Reject prose fragments sliced out of summary/footer lines
                if ($id -match '\s') { $id = $null }
            }
            if (-not $id) {
                # Fallback: last Publisher.Product-style token before version columns
                $idMatches = [regex]::Matches($line, '(?<![A-Za-z0-9_.+-])([A-Za-z][A-Za-z0-9_+-]*(?:\.[A-Za-z0-9][A-Za-z0-9_+-]*)+)(?![A-Za-z0-9_.+-])')
                if ($idMatches.Count -gt 0) {
                    $id = $idMatches[$idMatches.Count - 1].Groups[1].Value
                }
            }
            # Only accept real package Ids: Publisher.Product style, or msstore-style (e.g. 9WZDNCRFJ3TZ)
            $idValid = ($id -cmatch '^[A-Za-z][A-Za-z0-9_+-]*(?:\.[A-Za-z0-9][A-Za-z0-9_+-]*)+$') -or
                       ($id -cmatch '^[A-Z0-9]{8,16}$')
            if (-not $idValid -or $id -match '^(Name|Id|Version|Available|Source|winget|msstore)$' -or $id -match '^\d') { continue }

            $skip = $false
            foreach ($s in $wingetSkipIds) {
                if ($id -ieq $s) { $skip = $true; break }
            }
            if ($skip) {
                if (-not ($skipped -contains $id)) { [void]$skipped.Add($id) }
                continue
            }
            if (-not ($packageIds -contains $id)) {
                [void]$packageIds.Add($id)
                $packageLines += $line.Trim()
            }
        }
        if ($skipped.Count -gt 0) {
            Write-Info ("Skipping self-updating apps: {0}" -f (($skipped | Select-Object -Unique) -join ", "))
        }

        $countFromFooter = 0
        if ($listOut -match '(\d+)\s+upgrades?\s+available') { $countFromFooter = [int]$Matches[1] }
        $count = $packageIds.Count
        if ($count -eq 0) {
            if ($skipped.Count -gt 0) {
                Write-Ok "winget apps are up to date (only self-updating apps had upgrades; those are skipped)"
                return
            }
            if ($countFromFooter -gt 0) {
                Write-Warn "Could not parse package Ids from winget table - refusing bulk upgrade for safety"
                Write-Info "Re-run later, or upgrade specific apps with: winget upgrade --id <Id>"
                return
            }
            Write-Ok "winget apps are up to date"
            return
        }

        Write-Info ("Found {0} upgradeable package(s): {1}" -f $count, ($packageIds -join ", "))
        $preview = ($packageLines | Select-Object -First 12) -join "`n"
        if ($packageLines.Count -gt 12) { $preview += "`n..." }

        $msg = "winget will upgrade $count package(s) from the winget source (silent bulk upgrade).`n`nThis can update browsers, runtimes, and other apps.`nSelf-updaters (Roblox, Discord, Steam, Epic) are skipped.`n`nContinue?"
        if ($preview) { $msg += "`n`n" + $preview }
        $proceed = $true
        try {
            $r = Show-UiMessageBox `
                -Text $msg `
                -Caption "Confirm winget upgrades" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Question)
            $proceed = ($r -eq [System.Windows.Forms.DialogResult]::Yes)
        } catch {
            Write-Host $msg
            $ans = Read-Host "Continue with winget upgrades? (Y/N)"
            $proceed = ($ans -match '^[Yy]')
        }
        if (-not $proceed) {
            Write-Warn "winget upgrades skipped by user"
            return
        }

        Assert-NotCancelled
        Write-Info "Installing winget upgrades (bulk silent - much faster)..."
        $idsJoined = [string]::Join("`n", [string[]]@($packageIds))
        $skipJoined = [string]::Join("`n", [string[]]@($wingetSkipIds))
        $skippedJoined = [string]::Join("`n", [string[]]@($skipped))
        $outObj = Invoke-WithUiWait -Activity "winget upgrade" -TimeoutSec 1800 -ArgumentList @($winget, $skipJoined, $skippedJoined, $idsJoined) -ScriptBlock {
            param([string]$WingetPath, [string]$SkipJoined, [string]$SkippedJoined, [string]$IdsJoined)
            $skipIds = @()
            if ($SkipJoined -and $SkipJoined.Trim()) {
                $skipIds = @($SkipJoined -split "`n" | Where-Object { $_ -and $_.Trim() })
            }
            $mustPin = @()
            if ($SkippedJoined -and $SkippedJoined.Trim()) {
                $mustPin = @($SkippedJoined -split "`n" | Where-Object { $_ -and $_.Trim() })
            }
            $Ids = @()
            if ($IdsJoined -and $IdsJoined.Trim()) {
                $Ids = @($IdsJoined -split "`n" | Where-Object { $_ -and $_.Trim() })
            }

            function Invoke-WingetPerIdUpgrade {
                param([string]$WingetPath, [string[]]$Ids)
                $parts = New-Object System.Collections.Generic.List[string]
                $ok = 0
                $fail = 0
                $okIds = New-Object System.Collections.Generic.List[string]
                $failIds = New-Object System.Collections.Generic.List[string]
                foreach ($id in $Ids) {
                    [void]$parts.Add(("--- upgrading {0} ---" -f $id))
                    $text = & $WingetPath upgrade --id $id --exact --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
                    [void]$parts.Add($text)
                    if ($text -match "Successfully installed") {
                        $ok++
                        [void]$okIds.Add($id)
                    } elseif ($text -match "does not apply to your system") {
                        $fail++
                        [void]$failIds.Add("$id (not applicable to this PC)")
                    } elseif ($text -match "No applicable upgrade|No newer package versions") {
                        # already current
                    } else {
                        $fail++
                        [void]$failIds.Add($id)
                    }
                }
                return [pscustomobject]@{
                    Mode      = 'PerId'
                    Output    = ($parts -join "`n")
                    OkCount   = $ok
                    FailCount = $fail
                    OkIds     = ($okIds -join ", ")
                    FailIds   = ($failIds -join ", ")
                }
            }

            # Snapshot pins so we only remove ones we add
            $pinList = & $WingetPath pin list --disable-interactivity 2>&1 | Out-String
            $alreadyPinned = @{}
            foreach ($s in $skipIds) {
                if ($pinList -and ($pinList -match [regex]::Escape($s))) {
                    $alreadyPinned[$s] = $true
                }
            }

            $addedPins = New-Object System.Collections.Generic.List[string]
            $pinBlockFailed = New-Object System.Collections.Generic.List[string]
            try {
                foreach ($s in $skipIds) {
                    if ($alreadyPinned.ContainsKey($s)) { continue }
                    $pinOut = & $WingetPath pin add --id $s --exact --blocking --disable-interactivity --accept-source-agreements 2>&1 | Out-String
                    $pinOk = ($LASTEXITCODE -eq 0) -or ($pinOut -match '(?i)pin added|already exists|already pinned')
                    if ($pinOk) {
                        [void]$addedPins.Add($s)
                    } elseif ($mustPin -contains $s) {
                        # This self-updater has an available upgrade and we could not pin it -
                        # refuse bulk --all so we do not upgrade it by accident.
                        [void]$pinBlockFailed.Add($s)
                    }
                }

                if ($pinBlockFailed.Count -gt 0) {
                    $fallback = Invoke-WingetPerIdUpgrade -WingetPath $WingetPath -Ids $Ids
                    $fallback | Add-Member -NotePropertyName Note -NotePropertyValue ("Bulk skipped; could not pin: " + ($pinBlockFailed -join ', ')) -Force
                    return $fallback
                }

                $bulkText = & $WingetPath upgrade --all --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
                $bulkExit = $LASTEXITCODE
                $ok = ([regex]::Matches($bulkText, 'Successfully installed')).Count
                $upToDate = ($bulkText -match 'No applicable upgrade|No newer package versions|No installed package found matching input criteria') -and ($ok -eq 0)

                if ($ok -gt 0 -or $upToDate -or $bulkExit -eq 0) {
                    return [pscustomobject]@{
                        Mode      = 'Bulk'
                        Output    = $bulkText
                        OkCount   = $ok
                        FailCount = 0
                        OkIds     = ''
                        FailIds   = ''
                        Note      = 'Bulk silent upgrade (--source winget)'
                    }
                }

                # Bulk failed hard - fall back to per-id (still skips self-updaters)
                $fallback = Invoke-WingetPerIdUpgrade -WingetPath $WingetPath -Ids $Ids
                $fallback | Add-Member -NotePropertyName Note -NotePropertyValue 'Bulk failed; used per-id fallback' -Force
                $fallback.Output = ("--- bulk attempt ---`n" + $bulkText + "`n" + $fallback.Output)
                return $fallback
            } finally {
                foreach ($s in @($addedPins)) {
                    & $WingetPath pin remove --id $s --exact --disable-interactivity --accept-source-agreements 2>&1 | Out-Null
                }
            }
        }
        if ($null -eq $outObj) {
            Write-Warn "winget timed out or cancelled"
            return
        }
        $outPayload = @($outObj) | Select-Object -Last 1
        $out = ""
        $okCount = 0
        $failCount = 0
        $failIds = ""
        $mode = ""
        $note = ""
        try {
            $out = [string]$outPayload.Output
            $okCount = [int]$outPayload.OkCount
            $failCount = [int]$outPayload.FailCount
            $failIds = [string]$outPayload.FailIds
            try { $mode = [string]$outPayload.Mode } catch { }
            try { $note = [string]$outPayload.Note } catch { }
        } catch {
            $out = Get-AsyncResultText $outObj
            if ($out -match "Successfully installed") {
                $okCount = ([regex]::Matches($out, "Successfully installed")).Count
            }
        }

        if ($note) { Write-Info $note }
        if ($mode -eq 'Bulk' -and $okCount -eq 0 -and $failCount -eq 0) {
            Write-Ok "winget bulk upgrade finished (apps current or already newest)"
        } elseif ($okCount -gt 0) {
            Write-Ok ("winget upgraded {0} package(s)" -f $okCount)
        }
        if ($failCount -gt 0) {
            Write-Warn ("winget failed for {0} package(s): {1}" -f $failCount, $(if ($failIds) { $failIds } else { "check the activity panel" }))
        }
        if ($okCount -eq 0 -and $failCount -eq 0 -and $mode -ne 'Bulk') {
            Write-Ok "winget apps are up to date"
        } elseif ($okCount -eq 0 -and $failCount -gt 0) {
            Write-Warn "No packages were upgraded"
        }
    } catch {
        if ($_.Exception.Message -match 'Cancelled') { throw }
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

function Join-PathSafe {
    param([string]$Base, [string]$Child)
    if ([string]::IsNullOrWhiteSpace($Base)) { return $null }
    try {
        return [System.IO.Path]::Combine($Base.TrimEnd('\', '/'), $Child)
    } catch {
        return $null
    }
}

function Test-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        return [bool](Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
    } catch {
        return $false
    }
}

function Get-SteamDownloadingPaths {
    $roots = [System.Collections.Generic.List[string]]::new()
    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($regPath in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $install = (Get-ItemProperty $regPath -Name InstallPath -EA SilentlyContinue).InstallPath
            if ($install) { [void]$candidates.Add([string]$install) }
        } catch { }
    }

    # Only probe fallbacks whose drive actually exists (Join-Path throws on missing drives)
    $pf86 = ${env:ProgramFiles(x86)}
    $pf = $env:ProgramFiles
    foreach ($fallback in @(
        $(if ($pf86) { Join-PathSafe $pf86 'Steam' }),
        $(if ($pf) { Join-PathSafe $pf 'Steam' }),
        'C:\Program Files (x86)\Steam',
        'D:\Steam',
        'E:\Steam'
    )) {
        if (-not $fallback) { continue }
        if ($fallback -match '^[A-Za-z]:' -and -not (Test-PathSafe ($fallback.Substring(0, 1) + ':\'))) { continue }
        [void]$candidates.Add($fallback)
    }

    $seen = @{}
    foreach ($root in $candidates) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $key = $root.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        if ($root -match '^[A-Za-z]:' -and -not (Test-PathSafe ($root.Substring(0, 1) + ':\'))) { continue }

        $dl = Join-PathSafe $root 'steamapps\downloading'
        if ($dl -and (Test-PathSafe $dl)) { [void]$roots.Add($dl) }

        $vdf = Join-PathSafe $root 'steamapps\libraryfolders.vdf'
        if (-not $vdf -or -not (Test-PathSafe $vdf)) { continue }
        try {
            $text = [System.IO.File]::ReadAllText($vdf)
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $lib = ($m.Groups[1].Value -replace '\\\\', '\').Trim()
                if ([string]::IsNullOrWhiteSpace($lib)) { continue }
                $libKey = $lib.TrimEnd('\').ToLowerInvariant()
                if ($seen.ContainsKey($libKey)) { continue }
                $seen[$libKey] = $true
                if ($lib -match '^[A-Za-z]:' -and -not (Test-PathSafe ($lib.Substring(0, 1) + ':\'))) { continue }
                $libDl = Join-PathSafe $lib 'steamapps\downloading'
                if ($libDl -and (Test-PathSafe $libDl)) { [void]$roots.Add($libDl) }
            }
        } catch { }
    }
    return @($roots)
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
        $steamRoots = @(Get-SteamDownloadingPaths)
        if ($steamRoots.Count -eq 0) {
            Write-Info "Steam downloading folders not found"
        }
        foreach ($p in $steamRoots) {
            Write-Info "Steam downloading: $p"
            $freed = Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
            $total += $freed
        }
    }
    if ($Epic) {
        $epic = @(Get-EpicCachePaths)
        if ($epic.Count -eq 0) {
            # Fallback if Extras not loaded yet
            $epic = @(
                "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache",
                "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache_4430",
                "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs"
            )
        }
        foreach ($p in $epic) {
            if (-not (Test-PathSafe $p)) { continue }
            Write-Info "Epic: $p"
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
            if (-not (Test-PathSafe $p)) { continue }
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
        [void](Show-UiMessageBox `
            -Text "Windows has a pending restart (often after updates).`n`nRestart when you finish gaming for best stability." `
            -Caption "PC Maintenance - Restart recommended" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Information))
    } catch { }
}

function Get-SystemDisk {
    try {
        $partition = Get-Partition -DriveLetter C -EA Stop
        $phys = Get-PhysicalDisk -Number $partition.DiskNumber -EA SilentlyContinue
        if ($phys) { return $phys }
        return Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $partition.DiskNumber } | Select-Object -First 1
    } catch {
        try { return Get-PhysicalDisk | Select-Object -First 1 } catch { return $null }
    }
}

function Invoke-GamingChecks {
    # Read-only status + service health. Does NOT change Game DVR / ReLive
    # (those are only changed by Invoke-GamingOptimize).
    Write-Step "Quick health / gaming checks"
    try {
        $disk = Get-SystemDisk
        if ($disk) {
            Write-Ok ("System disk (C:): {0} - {1}" -f $disk.FriendlyName, $disk.HealthStatus)
        }
    } catch { }

    try {
        $power = (powercfg /getactivescheme) -replace '.*\((.+)\).*', '$1'
        Write-Ok "Power plan: $power"
    } catch { }

    $gamedvr = (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_Enabled -EA SilentlyContinue).GameDVR_Enabled
    if ($gamedvr -eq 0) {
        Write-Ok "Xbox Game DVR: Off"
    } elseif ($null -eq $gamedvr) {
        Write-Info "Xbox Game DVR: Unknown"
    } else {
        Write-Info "Xbox Game DVR: On (use Gaming optimize to turn off)"
    }

    $relive = (Get-ItemProperty "HKCU:\Software\AMD\DVR" -Name DvrEnabled -EA SilentlyContinue).DvrEnabled
    if ($null -eq $relive) {
        Write-Info "AMD ReLive key not present"
    } elseif ($relive -eq 0) {
        Write-Ok "AMD ReLive: Off"
    } else {
        Write-Info "AMD ReLive: On (use Gaming optimize to turn off)"
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

function Confirm-RepairAction {
    param(
        [string]$ModeName = 'Repair',
        [switch]$Gui
    )
    $label = if ($ModeName -eq 'FullRepair') {
        'Full Repair (cleanup + updates + DISM/SFC)'
    } else {
        'Windows Repair (DISM + SFC)'
    }
    if ($Gui) {
        try {
            $r = Show-UiMessageBox `
                -Text ("{0}`n`nThis can take 15-60+ minutes and may require a restart.`nA restore point is recommended.`nYou can press Stop to abort.`n`nContinue?" -f $label) `
                -Caption "Confirm repair" `
                -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
            return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
        } catch {
            return $false
        }
    }

    Write-Host ""
    Write-Host ("  WARNING: {0}" -f $label) -ForegroundColor Yellow
    Write-Host "  This can take a long time and may require a restart." -ForegroundColor DarkYellow
    Write-Host "  Type YES (all caps) to continue, anything else to cancel." -ForegroundColor DarkGray
    $ans = Read-Host "  Confirm"
    return ($ans -eq 'YES')
}

function Invoke-Repair {
    Write-Step "Windows Repair (DISM + SFC)"
    Write-Info "This can take 10-30+ minutes. Do not close the window."
    Assert-NotCancelled

    try {
        Write-Info "DISM /RestoreHealth starting..."
        $dismLog = Join-Path (Get-AppTempDirectory) "dism_$(Get-Date -Format 'HHmmss').log"
        $p = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online","/Cleanup-Image","/RestoreHealth","/LogPath:$dismLog" -PassThru -NoNewWindow
        Register-TrackedProcess $p
        $spin = @('|','/','-','\'); $i = 0
        while (-not $p.HasExited) {
            if (Test-CancelRequested) {
                try { $p.Kill() } catch { }
                Write-Warn "DISM cancelled"
                return
            }
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
        if ($_.Exception.Message -match 'Cancelled') { throw }
        Write-Fail "DISM failed: $($_.Exception.Message)"
    }

    Assert-NotCancelled
    try {
        Write-Info "SFC /scannow starting..."
        $p = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -PassThru -NoNewWindow
        Register-TrackedProcess $p
        $spin = @('|','/','-','\'); $i = 0
        while (-not $p.HasExited) {
            if (Test-CancelRequested) {
                try { $p.Kill() } catch { }
                Write-Warn "SFC cancelled"
                return
            }
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
            Write-Warn "SFC finished with exit $code - see CBS.log if issues persist"
        }
    } catch {
        if ($_.Exception.Message -match 'Cancelled') { throw }
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
        ""
    )
    foreach ($line in $Script:Report) { $lines += $line }
    return ($lines -join "`r`n")
}

function Invoke-MaintenanceRun {
    $Script:CancelRequested = $false
    if ($Script:UiShare) { $Script:UiShare['CancelRequested'] = $false }
    Clear-TrackedProcesses
    $Script:Report.Clear()
    $Script:RunStart = Get-Date
    Build-StepPlan
    $Script:StartFree = Get-CFreeGB

    Write-Info "C: free space before: $($Script:StartFree) GB"
    Write-Info ("Plan: " + ($Script:StepNames -join " > "))

    try {
        if ($Script:DoRestorePoint) { New-MaintenanceRestorePoint; Assert-NotCancelled }
        if ($Script:DoCleanup) {
            Invoke-TempCleanup
            Assert-NotCancelled
            Invoke-BrowserCacheCleanup
            Assert-NotCancelled
            Invoke-RecycleAndCleanMgr
        }
        if ($Script:DoShaderCleanup) { Assert-NotCancelled; Invoke-ShaderCacheCleanup }
        if ($Script:DoWinUpdate) { Assert-NotCancelled; Invoke-WindowsUpdate }
        if ($Script:DoWinget) { Assert-NotCancelled; Invoke-WingetUpdates }
        if ($Script:DoAmd) { Assert-NotCancelled; Invoke-AmdOpen }
        if ($Script:DoRepair) { Assert-NotCancelled; Invoke-Repair }
        if ($Script:DoGamingOptimize) {
            Assert-NotCancelled
            if (Get-Command Invoke-GamingOptimize -EA SilentlyContinue) {
                Invoke-GamingOptimize
            }
        }

        Assert-NotCancelled
        Invoke-GamingChecks
    } catch {
        if ($_.Exception.Message -match 'Cancelled') {
            Write-Warn "Run cancelled by user"
        } else {
            throw
        }
    }

    $Script:CurrentStep = $Script:TotalSteps
    Update-UiProgress -Label "DONE"
    $summary = Get-RunSummaryText
    Write-Host ""
    Write-Host $summary
    Append-UiLog ""
    Append-UiLog "======== DONE ========" "Green"
    Append-UiLog $summary "Cyan"
    if (-not (Test-CancelRequested)) {
        Show-RebootRecommendedDialog
        if (Get-Command Show-RunSummaryDialog -EA SilentlyContinue) {
            Show-RunSummaryDialog -Title "PC Maintenance - Summary" -Summary (Get-RunSummaryObject)
        }
    }
    Clear-TrackedProcesses
    return $summary
}
