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
$Script:HeadlessRun = $false
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
# Process ids that Stop must not kill. DISM and SFC finish on their own.
$Script:TrackedLeaveRunning = @{}
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
    $leftRunning = $false
    foreach ($p in @($Script:TrackedProcesses)) {
        try {
            if (-not $p -or $p.HasExited) { continue }
            if ($Script:TrackedLeaveRunning -and $Script:TrackedLeaveRunning.ContainsKey([string]$p.Id)) {
                $leftRunning = $true
            }
        } catch { }
    }
    if ($Script:BgLeaveRunning) { $leftRunning = $true }
    if ($leftRunning) {
        Write-Warn "Stop will not kill DISM, SFC, winget, or Windows Update once that step has started. It keeps running until it finishes. Later steps are skipped."
    } else {
        if ($Script:BgPowerShell) {
            try { $Script:BgPowerShell.Stop() } catch {
                Write-Warn ("Could not stop the background step: {0}" -f $_.Exception.Message)
            }
        }
        Write-Warn "Cancel requested - stopping after current step..."
    }
}

function Assert-NotCancelled {
    if (Test-CancelRequested) {
        throw "Cancelled by user."
    }
}

function Register-TrackedProcess {
    param(
        [System.Diagnostics.Process]$Process,
        [switch]$LeaveRunning
    )
    if ($Process) {
        try { [void]$Script:TrackedProcesses.Add($Process) } catch { }
        if ($LeaveRunning) {
            if (-not $Script:TrackedLeaveRunning) { $Script:TrackedLeaveRunning = @{} }
            $Script:TrackedLeaveRunning[[string]$Process.Id] = $true
        }
    }
}

function Clear-TrackedProcesses {
    try { $Script:TrackedProcesses.Clear() } catch { }
    $Script:TrackedLeaveRunning = @{}
}

function Enqueue-UiEvent {
    param([hashtable]$UiEvent)
    if (-not $Script:UiShare -or -not $Script:UiShare.Queue) { return $false }
    # Already on the UI thread: let the caller apply immediately (snappier Activity log).
    $form = Get-UiControl Form
    if ($form -and -not $form.IsDisposed) {
        try {
            if (-not $form.InvokeRequired) { return $false }
        } catch { }
    }
    $Script:UiShare.Queue.Enqueue($UiEvent)
    return $true
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
    if (Get-Command Drain-UiEventQueue -EA SilentlyContinue) {
        try { Drain-UiEventQueue } catch { }
    }
    $form = Get-UiControl Form
    if ($form -and -not $form.IsDisposed) {
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Pump-UiThrottled {
    $now = [datetime]::UtcNow
    if (($now - $Script:LastPumpUtc).TotalMilliseconds -lt 120) { return }
    $Script:LastPumpUtc = $now
    Pump-Ui
}

function Format-UiByteSize([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ("{0:N1} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N0} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N0} KB" -f ($Bytes / 1KB)) }
    return ("{0:N0} B" -f $Bytes)
}

function Update-UiSubProgress {
    param([double]$Fraction = 0)
    # Map 0..1 into the current Write-Step slice (e.g. step 2/5 -> 20..40%).
    if ($Script:TotalSteps -le 0 -or $Script:CurrentStep -le 0) { return }
    $frac = [math]::Max(0.0, [math]::Min(1.0, $Fraction))
    $step = [int]$Script:CurrentStep
    $total = [int]$Script:TotalSteps
    $base = (($step - 1) / [double]$total) * 100.0
    $span = (1.0 / [double]$total) * 100.0
    $pct = [math]::Min(100, [math]::Round($base + ($span * $frac)))
    Set-UiProgressValue -Value ([int]$pct)
}

function Update-CleanupLiveStatus {
    param(
        [string]$PathLabel,
        [int]$Files,
        [long]$Bytes
    )
    $plain = ("Cleaning: {0}  |  {1:N0} files  |  {2}" -f $PathLabel, $Files, (Format-UiByteSize $Bytes))
    Set-UiStatusText -Text $plain
    if (Get-Command Update-GuiStatusBar -EA SilentlyContinue) {
        Update-GuiStatusBar -JobText $plain
    }
    if ($Files -gt 0) {
        # Unknown total file count: asymptotic fill within the current step.
        $soft = [math]::Min(0.92, 1.0 - (1.0 / (1.0 + ($Files / 120.0))))
        Update-UiSubProgress -Fraction $soft
    }
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
    if (Get-Command Set-PageLiveStatus -EA SilentlyContinue) {
        try { Set-PageLiveStatus -Text $Text } catch { }
    }
}

function Invoke-WithUiWait {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Activity = "Working",
        [int]$TimeoutSec = 900,
        [object[]]$ArgumentList = @(),
        [switch]$Sta,
        [switch]$LeaveRunning
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
    $Script:BgLeaveRunning = [bool]$LeaveRunning
    [void]$ps.AddScript($ScriptBlock)
    foreach ($a in $ArgumentList) {
        [void]$ps.AddArgument($a)
    }
    $handle = $ps.BeginInvoke()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $spin = @('|','/','-','\')
    $i = 0
    $lastHbSec = -15
    $notedStop = $false
    $notedTimeout = $false
    try {
        while (-not $handle.IsCompleted) {
            if (Test-CancelRequested -and -not $LeaveRunning) {
                try { $ps.Stop() } catch {
                    Write-Warn ("Could not stop {0}: {1}" -f $Activity, $_.Exception.Message)
                }
                Write-Warn "$Activity cancelled"
                return $null
            }
            if ($sw.Elapsed.TotalSeconds -ge $TimeoutSec) {
                if ($LeaveRunning) {
                    if (-not $notedTimeout) {
                        $notedTimeout = $true
                        Write-Warn "$Activity is past ${TimeoutSec}s. Stop leaves it running until it finishes."
                    }
                } else {
                    try { $ps.Stop() } catch {
                        Write-Warn ("Could not stop {0}: {1}" -f $Activity, $_.Exception.Message)
                    }
                    Write-Warn "$Activity timed out after ${TimeoutSec}s"
                    return $null
                }
            }
            if (Test-CancelRequested -and $LeaveRunning -and -not $notedStop) {
                $notedStop = $true
                Write-Warn "$Activity keeps running after Stop. Later steps are skipped when it finishes."
            }
            $sec = [int]$sw.Elapsed.TotalSeconds
            $ch = $spin[$i % 4]
            Set-UiStatusText ("[{0}] {1}... {2}s" -f $ch, $Activity, $sec)
            if (($sec - $lastHbSec) -ge 15) {
                $lastHbSec = $sec
                $hint = if ($LeaveRunning) { 'Stop skips later steps' } else { 'Stop to cancel' }
                Write-Info ("{0} still running... {1}s ({2})" -f $Activity, $sec, $hint)
            }
            Write-Host -NoNewline ("`r  [{0}] {1}... {2}s   " -f $ch, $Activity, $sec) -ForegroundColor DarkYellow
            Pump-Ui
            Start-Sleep -Milliseconds 350
            $i++
        }
        Write-Host ""
        if (Test-CancelRequested -and -not $LeaveRunning) {
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
        $Script:BgLeaveRunning = $false
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
        'Gray'   { return [System.Drawing.Color]::FromArgb(176, 190, 208) }
        default  { return [System.Drawing.Color]::FromArgb(244, 247, 251) }
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

function Get-SystemLogicalDisk {
    param([switch]$Refresh)
    # One C: read feeds free space, capacity, and the file system. Free space is
    # allowed to go stale after 8 seconds; capacity is kept from that same read.
    if (-not $Refresh -and $null -ne $Script:LogicalDiskCache -and (([datetime]::UtcNow - $Script:LogicalDiskCacheUtc).TotalSeconds -lt 8)) {
        return $Script:LogicalDiskCache
    }
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    $Script:LogicalDiskCache = $d
    $Script:LogicalDiskCacheUtc = [datetime]::UtcNow
    if ($d -and $d.Size -gt 0) {
        $Script:DriveCapacityGbCache = [math]::Round(([double]$d.Size) / 1GB, 1)
        $Script:DriveCapacityGbCacheUtc = [datetime]::UtcNow
    }
    return $d
}

function Get-CFreeGB {
    param([switch]$Refresh)
    if (-not $Refresh -and $null -ne $Script:CFreeGBCache -and (([datetime]::UtcNow - $Script:CFreeGBCacheUtc).TotalSeconds -lt 8)) {
        return $Script:CFreeGBCache
    }
    $d = Get-SystemLogicalDisk -Refresh:$Refresh
    $val = 0
    if ($d -and $null -ne $d.FreeSpace) {
        $val = [math]::Round($d.FreeSpace / 1GB, 1)
    }
    $Script:CFreeGBCache = $val
    $Script:CFreeGBCacheUtc = [datetime]::UtcNow
    return $val
}

function Get-SystemDriveCapacityGB {
    param([switch]$Refresh)
    if (-not $Refresh -and $null -ne $Script:DriveCapacityGbCache -and (([datetime]::UtcNow - $Script:DriveCapacityGbCacheUtc).TotalSeconds -lt 600)) {
        return $Script:DriveCapacityGbCache
    }
    $d = Get-SystemLogicalDisk -Refresh:$Refresh
    if ($d -and $d.Size -gt 0) {
        return $Script:DriveCapacityGbCache
    }
    return $null
}

function Select-UniqueCleanupPaths {
    # %TEMP% and LocalAppData\Temp are often the same folder. Walk it once.
    param([string[]]$Paths)
    $out = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($p in $Paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $full = $null
        try { $full = [System.IO.Path]::GetFullPath($p).TrimEnd('\') } catch { continue }
        $key = $full.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        if (-not (Test-PathSafe $full)) { continue }
        $seen[$key] = $true
        [void]$out.Add($full)
    }
    return @($out.ToArray())
}

function Get-RebootPendingInfo {
    param([switch]$Refresh)
    # Hard signals only. PendingFileRenameOperations is intentionally ignored:
    # InstallShield, Xbox Gaming Services, and temp uninstallers leave stale
    # rename entries for months, so almost every gamer PC looks "reboot pending"
    # forever and Hygiene falsely floors at 30/100.
    if (-not $Refresh -and $null -ne $Script:RebootPendingInfoCache -and (([datetime]::UtcNow - $Script:RebootPendingInfoCacheUtc).TotalSeconds -lt 10)) {
        return $Script:RebootPendingInfoCache
    }
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        [void]$reasons.Add('Windows Update')
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        [void]$reasons.Add('Component Servicing (CBS)')
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\RebootRequired") {
        [void]$reasons.Add('Update Orchestrator')
    }
    $info = [pscustomobject]@{
        Pending = ($reasons.Count -gt 0)
        Reasons = [string[]]@($reasons.ToArray())
    }
    $Script:RebootPendingInfoCache = $info
    $Script:RebootPendingInfoCacheUtc = [datetime]::UtcNow
    return $info
}

function Test-RebootPending {
    param([switch]$Refresh)
    return [bool]((Get-RebootPendingInfo -Refresh:$Refresh).Pending)
}

function Clear-HardwareProbeCaches {
    $Script:CFreeGBCache = $null
    $Script:CFreeGBCacheUtc = [datetime]::MinValue
    $Script:LogicalDiskCache = $null
    $Script:LogicalDiskCacheUtc = [datetime]::MinValue
    $Script:DriveCapacityGbCache = $null
    $Script:DriveCapacityGbCacheUtc = [datetime]::MinValue
    $Script:VideoControllerCache = $null
    $Script:SystemDiskCache = $null
    $Script:SystemDiskCacheUtc = [datetime]::MinValue
    $Script:PrimaryVideoCache = $null
    $Script:PrimaryVideoCacheUtc = [datetime]::MinValue
    $Script:PowerPlanCache = $null
    $Script:PowerPlanCacheUtc = [datetime]::MinValue
    $Script:RebootPendingInfoCache = $null
    $Script:RebootPendingInfoCacheUtc = [datetime]::MinValue
    $Script:ProtectedCleanupPathsCache = $null
    $Script:DeviceSummaryCache = $null
    $Script:DeviceSummaryCacheUtc = [datetime]::MinValue
    $Script:SecurityHealthCache = $null
    $Script:SecurityHealthCacheUtc = [datetime]::MinValue
    $Script:AutoServiceCache = $null
    $Script:AutoServiceCacheUtc = [datetime]::MinValue
    $Script:LogonTaskCache = $null
    $Script:LogonTaskCacheUtc = [datetime]::MinValue
    $Script:OptimizationScoreCache = $null
    $Script:OptimizationScoreCacheUtc = [datetime]::MinValue
    $Script:CleanupPreviewCache = $null
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
    if ($null -ne $Script:ProtectedCleanupPathsCache) {
        return ,$Script:ProtectedCleanupPathsCache
    }
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
    $Script:ProtectedCleanupPathsCache = $list
    return ,$list
}

function Get-WindowsTempPath {
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        return (Join-Path $env:SystemRoot 'Temp')
    }
    return 'C:\Windows\Temp'
}

function Get-WindowsUpdateDownloadPath {
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        return (Join-Path $env:SystemRoot 'SoftwareDistribution\Download')
    }
    return 'C:\Windows\SoftwareDistribution\Download'
}

function Test-NormalizedPathUnder {
    param([string]$ChildKey, [string]$ParentPath)
    if ([string]::IsNullOrWhiteSpace($ChildKey) -or [string]::IsNullOrWhiteSpace($ParentPath)) { return $false }
    $parentFull = $null
    try { $parentFull = [System.IO.Path]::GetFullPath($ParentPath) } catch { return $false }
    if ([string]::IsNullOrWhiteSpace($parentFull)) { return $false }
    $parentKey = $parentFull.TrimEnd('\', '/').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($parentKey)) { return $false }
    if ($ChildKey -eq $parentKey) { return $true }
    return $ChildKey.StartsWith($parentKey + '\')
}

function Test-FileReparsePoint {
    param($Info)
    if ($null -eq $Info) { return $true }
    try {
        return (($Info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    } catch {
        return $true
    }
}

function Test-CleanupPathContained {
    # True only when Candidate is strictly inside Root. Prefix match uses a trailing
    # separator so C:\temp does not contain C:\temp-other.
    param([string]$RootFull, [string]$CandidateFull)
    if ([string]::IsNullOrWhiteSpace($RootFull) -or [string]::IsNullOrWhiteSpace($CandidateFull)) { return $false }
    $root = $RootFull.TrimEnd('\', '/')
    $cand = $CandidateFull.TrimEnd('\', '/')
    if ($cand.Length -le $root.Length) { return $false }
    $prefix = $root + '\'
    return $cand.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-ContainedTreeWalk {
    # Walks $Root without following directory junctions or symlinks. File reparse
    # points are skipped too. Returns how many reparse points were left untouched.
    param(
        [Parameter(Mandatory)][string]$Root,
        [scriptblock]$OnFile,
        [scriptblock]$OnDirectory
    )
    $skipped = 0
    $rootFull = $null
    try { $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') } catch { return 0 }
    $rootInfo = $null
    try { $rootInfo = [System.IO.DirectoryInfo]::new($rootFull) } catch { return 0 }
    if (-not $rootInfo.Exists) { return 0 }

    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($rootFull)
    while ($stack.Count -gt 0) {
        if (Test-CancelRequested) { break }
        $current = [string]$stack.Pop()
        $currentTrim = $current.TrimEnd('\')
        if (($currentTrim -ne $rootFull) -and -not (Test-CleanupPathContained -RootFull $rootFull -CandidateFull $currentTrim)) {
            continue
        }
        $di = $null
        try { $di = [System.IO.DirectoryInfo]::new($currentTrim) } catch { continue }
        if (-not $di.Exists) { continue }
        if (($currentTrim -ne $rootFull) -and (Test-FileReparsePoint $di)) {
            $skipped++
            continue
        }

        try {
            foreach ($f in $di.EnumerateFiles()) {
                if (Test-FileReparsePoint $f) { $skipped++; continue }
                if (-not (Test-CleanupPathContained -RootFull $rootFull -CandidateFull $f.FullName)) { continue }
                if ($OnFile) { & $OnFile $f }
            }
        } catch { }

        try {
            foreach ($sub in $di.EnumerateDirectories()) {
                if (Test-FileReparsePoint $sub) { $skipped++; continue }
                if (-not (Test-CleanupPathContained -RootFull $rootFull -CandidateFull $sub.FullName)) { continue }
                if ($OnDirectory) { & $OnDirectory $sub }
                $stack.Push($sub.FullName)
            }
        } catch { }
    }
    return $skipped
}

function Measure-ContainedTreeBytes {
    # Same safety rules as Invoke-ContainedTreeWalk, without a PowerShell call per file.
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$OlderThanDays = 0
    )
    $sum = [int64]0
    $rootFull = $null
    try { $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') } catch { return $sum }
    $rootInfo = $null
    try { $rootInfo = [System.IO.DirectoryInfo]::new($rootFull) } catch { return $sum }
    if (-not $rootInfo.Exists) { return $sum }

    $cutoff = $null
    if ($OlderThanDays -gt 0) { $cutoff = (Get-Date).AddDays(-$OlderThanDays) }
    $label = Split-Path $rootFull -Leaf
    if ([string]::IsNullOrWhiteSpace($label)) { $label = $rootFull }
    $n = 0
    $cancelled = $false
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($rootFull)
    while ($stack.Count -gt 0) {
        if (Test-CancelRequested) { break }
        $current = [string]$stack.Pop()
        $currentTrim = $current.TrimEnd('\')
        if (($currentTrim -ne $rootFull) -and -not (Test-CleanupPathContained -RootFull $rootFull -CandidateFull $currentTrim)) {
            continue
        }
        $di = $null
        try { $di = [System.IO.DirectoryInfo]::new($currentTrim) } catch { continue }
        if (-not $di.Exists) { continue }
        if (($currentTrim -ne $rootFull) -and (Test-FileReparsePoint $di)) { continue }

        try {
            foreach ($f in $di.EnumerateFiles()) {
                if (Test-FileReparsePoint $f) { continue }
                if (-not (Test-CleanupPathContained -RootFull $rootFull -CandidateFull $f.FullName)) { continue }
                if ($null -ne $cutoff) {
                    try { if ($f.LastWriteTime -ge $cutoff) { continue } } catch { continue }
                }
                try { $sum += [int64]$f.Length } catch { }
                $n++
                if (($n % 2000) -eq 0) {
                    if (Test-CancelRequested) { $cancelled = $true; break }
                    $status = ("Measuring {0}  |  {1:N0} files  |  {2}" -f $label, $n, (Format-UiByteSize $sum))
                    if (Get-Command Set-UiStatusText -EA SilentlyContinue) { Set-UiStatusText $status }
                    if (Get-Command Update-GuiStatusBar -EA SilentlyContinue) { Update-GuiStatusBar -JobText $status }
                    if (Get-Command Pump-UiThrottled -EA SilentlyContinue) { Pump-UiThrottled }
                }
            }
        } catch { }
        if ($cancelled) { break }

        try {
            foreach ($sub in $di.EnumerateDirectories()) {
                if (Test-FileReparsePoint $sub) { continue }
                if (-not (Test-CleanupPathContained -RootFull $rootFull -CandidateFull $sub.FullName)) { continue }
                $stack.Push($sub.FullName)
            }
        } catch { }
    }
    return $sum
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

    # Shallowest path we ever clean is Windows\Temp - two segments below the root
    $segments = @($norm -split '[\\/]+' | Where-Object { $_ -and $_ -notmatch '^[A-Za-z]:$' })
    if ($segments.Count -lt 2) { return $false }

    # Exact denylist does not cover children. Refuse whole trees we never mean to clean.
    foreach ($name in @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Videos', 'Music', 'Saved Games')) {
        $folder = Join-PathSafe $env:USERPROFILE $name
        if ($folder -and (Test-NormalizedPathUnder -ChildKey $key -ParentPath $folder)) { return $false }
    }
    $programs = Join-PathSafe $env:LOCALAPPDATA 'Programs'
    if ($programs -and (Test-NormalizedPathUnder -ChildKey $key -ParentPath $programs)) { return $false }
    if ($env:PUBLIC -and (Test-NormalizedPathUnder -ChildKey $key -ParentPath $env:PUBLIC)) { return $false }

    $drive = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\') } else { $null }
    $usersRoot = if ($drive) { ($drive + '\Users') } else { $null }
    if ($usersRoot -and (Test-NormalizedPathUnder -ChildKey $key -ParentPath $usersRoot)) {
        if (-not ($env:USERPROFILE -and (Test-NormalizedPathUnder -ChildKey $key -ParentPath $env:USERPROFILE))) {
            return $false
        }
    }

    # Under Windows, only Temp and the Update download cache are eligible.
    if ($env:SystemRoot -and (Test-NormalizedPathUnder -ChildKey $key -ParentPath $env:SystemRoot)) {
        $winTemp = Get-WindowsTempPath
        $winUpdate = Get-WindowsUpdateDownloadPath
        $underTemp = Test-NormalizedPathUnder -ChildKey $key -ParentPath $winTemp
        $underUpdate = Test-NormalizedPathUnder -ChildKey $key -ParentPath $winUpdate
        if (-not $underTemp -and -not $underUpdate) { return $false }
    }

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
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    Assert-NotCancelled
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $acc = @{ Freed = [long]0; N = 0; LastLogN = 0; Failed = 0 }
    $label = Split-Path $Path -Leaf
    if ([string]::IsNullOrWhiteSpace($label)) { $label = $Path }
    Update-CleanupLiveStatus -PathLabel $label -Files 0 -Bytes 0
    Pump-UiThrottled

    $dirs = [System.Collections.Generic.List[string]]::new()
    # GetNewClosure binds $acc/$dirs into the callbacks. A bare scriptblock would
    # run in the walker's scope and miss these locals.
    $onFile = {
        param($f)
        if (Test-CancelRequested) { return }
        if ($OlderThanDays -gt 0 -and $f.LastWriteTime -ge $cutoff) { return }
        $len = 0L
        try { $len = [long]$f.Length } catch { }
        try {
            # Remove-Item -Force clears ReadOnly; FileInfo.Delete() does not.
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $acc.Freed = [long]$acc.Freed + $len
            $acc.N = [int]$acc.N + 1
        } catch {
            $acc.Failed = [int]$acc.Failed + 1
        }
        $nNow = [int]$acc.N
        if (($nNow % 80) -eq 0 -and $nNow -gt 0) {
            Assert-NotCancelled
            Update-CleanupLiveStatus -PathLabel $label -Files $nNow -Bytes ([long]$acc.Freed)
            Pump-UiThrottled
        }
        if (($nNow - [int]$acc.LastLogN) -ge 250) {
            $acc.LastLogN = $nNow
            Write-Info ("{0}: {1:N0} files, {2} so far..." -f $label, $nNow, (Format-UiByteSize ([long]$acc.Freed)))
        }
    }.GetNewClosure()
    $onDir = {
        param($d)
        if ($DeleteFoldersToo) { [void]$dirs.Add($d.FullName) }
    }.GetNewClosure()
    # Manual walk: AllDirectories follows junctions, and a prefix check on the
    # path you used to get there still looks "inside" the approved folder.
    $skipped = Invoke-ContainedTreeWalk -Root $Path -OnFile $onFile -OnDirectory $onDir

    $freed = [long]$acc.Freed
    $n = [int]$acc.N
    if ($skipped -gt 0) {
        Write-Info ("{0}: skipped {1} reparse point(s)" -f $label, $skipped)
    }
    if ([int]$acc.Failed -gt 0) {
        Write-Warn ("{0}: {1:N0} file(s) were in use and could not be deleted." -f $label, [int]$acc.Failed)
    }
    if ($n -gt 0) {
        Update-CleanupLiveStatus -PathLabel $label -Files $n -Bytes $freed
        Pump-UiThrottled
    }
    if (Test-CancelRequested) { return $freed }
    if ($DeleteFoldersToo) {
        $dirN = 0
        $rootFull = $null
        try { $rootFull = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { $rootFull = $null }
        # Deepest paths first so parents empty after children are removed.
        $sorted = @($dirs | Sort-Object { $_.Length } -Descending)
        foreach ($dirPath in $sorted) {
            if (Test-CancelRequested) { break }
            if ($rootFull -and -not (Test-CleanupPathContained -RootFull $rootFull -CandidateFull $dirPath)) { continue }
            try {
                $di = [System.IO.DirectoryInfo]::new($dirPath)
                if (-not $di.Exists) { continue }
                if (Test-FileReparsePoint $di) { continue }
                if (($di.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
                    $di.Attributes = ($di.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly))
                }
                # non-recursive: only succeeds when empty (no per-dir listing probe)
                [System.IO.Directory]::Delete($dirPath, $false)
            } catch { }
            $dirN++
            if (($dirN % 60) -eq 0) { Pump-UiThrottled }
        }
    }
    return $freed
}

function Invoke-TempCleanup {
    Write-Step "Cleaning temp files (older than $($Script:TempOlderThanDays) day(s))"
    $total = 0L
    # GPU shader caches are handled only by Invoke-ShaderCacheCleanup (checkbox-driven).
    # Internet cache and the Windows web database stay. They are profile data, not temp files.
    $paths = @(Select-UniqueCleanupPaths -Paths @(
        $env:TEMP,
        "$env:LOCALAPPDATA\Temp",
        (Get-WindowsTempPath),
        "$env:LOCALAPPDATA\CrashDumps"
    ))

    $i = 0
    foreach ($p in $paths) {
        $i++
        Write-Info ("[{0}/{1}] Scanning {2}" -f $i, $paths.Count, $p)
        Pump-Ui
        $freed = Remove-OldFilesInPath -Path $p -OlderThanDays $Script:TempOlderThanDays -DeleteFoldersToo
        $total += $freed
        if ($freed -gt 0) {
            Write-Ok ("{0}: freed {1}" -f (Split-Path $p -Leaf), (Format-UiByteSize $freed))
        } else {
            Write-Info ("{0}: nothing to remove" -f (Split-Path $p -Leaf))
        }
    }

    try {
        if (-not $Script:DoWuCacheWipe) {
            Write-Info "Skipped Windows Update download-cache wipe (opt-in on Cleanup tab)"
        } elseif ($Script:DoWinUpdate) {
            Write-Info "Skipped Windows Update download-cache wipe (updates will run next)"
        } else {
            Write-Info "Clearing Windows Update download cache..."
            $do = Get-WindowsUpdateDownloadPath
            if ($do -and (Assert-SafeCleanupPath -Path $do -Operation 'update cache wipe') -and (Test-Path -LiteralPath $do)) {
                $wuStopped = $false
                $bitsStopped = $false
                try {
                    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                    $wuStopped = $true
                    Stop-Service bits -Force -ErrorAction SilentlyContinue
                    $bitsStopped = $true
                    Start-Sleep -Seconds 2
                    $freeBefore = Get-CFreeGB -Refresh
                    # Same contained walk as every other delete. Do not Remove-Item -Recurse.
                    [void](Remove-OldFilesInPath -Path $do -OlderThanDays 0 -DeleteFoldersToo)
                    $freeAfter = Get-CFreeGB -Refresh
                    $approxBytes = [math]::Max(0L, [long](($freeAfter - $freeBefore) * 1GB))
                    $total += $approxBytes
                    if ($approxBytes -gt 0) {
                        Write-Ok ("Update download cache: about {0}" -f (Format-UiByteSize $approxBytes))
                    } else {
                        Write-Ok "Update download cache cleared"
                    }
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

    $browserNames = @($browserPaths.Keys)
    $bi = 0
    foreach ($browser in $browserNames) {
        $bi++
        Write-Info ("[{0}/{1}] Checking {2}..." -f $bi, $browserNames.Count, $browser)
        Pump-Ui
        $freedBrowser = 0L
        foreach ($p in $browserPaths[$browser]) {
            if (-not (Test-PathSafe $p)) { continue }
            $freedBrowser += Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
        }
        if ($freedBrowser -gt 0) {
            $total += $freedBrowser
            Write-Ok ("{0}: freed {1}" -f $browser, (Format-UiByteSize $freedBrowser))
        } else {
            Write-Info ("{0}: nothing to remove (or files locked)" -f $browser)
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
            $install = Invoke-WithUiWait -Activity "Installing Windows Updates" -TimeoutSec 3600 -Sta -LeaveRunning -ScriptBlock {
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

function ConvertFrom-WingetUpgradeList {
    # winget prints three tables. "upgrade --all" only installs the first.
    # Unity editors and similar packages sit in "explicit targeting" and are skipped with no error.
    param([string]$Text)
    $bulk = New-Object System.Collections.Generic.List[string]
    $explicit = New-Object System.Collections.Generic.List[string]
    $unknown = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    $section = 'bulk'
    $idCol = -1
    $verCol = -1
    $availCol = -1
    $srcCol = -1
    foreach ($line in ([string]$Text -split "`r?`n")) {
        if ($line -match '^\s*$') { continue }
        if ($line -match '(?i)explicit targeting') { $section = 'explicit'; $idCol = -1; $verCol = -1; $availCol = -1; $srcCol = -1; continue }
        if ($line -match '(?i)cannot be determined') { $section = 'unknown'; $idCol = -1; $verCol = -1; $availCol = -1; $srcCol = -1; continue }
        if ($line -match '^Name\s+Id\s+Version') {
            $idCol = $line.IndexOf('Id')
            $verCol = $line.IndexOf('Version')
            $availCol = $line.IndexOf('Available')
            $srcCol = $line.IndexOf('Source')
            continue
        }
        if ($line -match '^-+' -or $line -match '\d\s+upgrades?\s+available' -or $line -match '^\s*\d+\s+package' -or $line -match 'The following packages' -or $line -match 'have an upgrade available' -or $line -match 'No installed package found' -or $line -match 'No newer package versions') {
            continue
        }

        $id = $null
        if ($idCol -ge 0 -and $verCol -gt $idCol -and $line.Length -gt $idCol) {
            $end = [Math]::Min($verCol, $line.Length)
            $id = $line.Substring($idCol, $end - $idCol).Trim()
            if ($id -match '\s') { $id = $null }
        }
        if (-not $id) {
            $idMatches = [regex]::Matches($line, '(?<![A-Za-z0-9_.+-])([A-Za-z][A-Za-z0-9_+-]*(?:\.[A-Za-z0-9][A-Za-z0-9_+-]*)+)(?![A-Za-z0-9_.+-])')
            if ($idMatches.Count -gt 0) {
                $id = $idMatches[$idMatches.Count - 1].Groups[1].Value
            }
        }
        $idValid = ($id -cmatch '^[A-Za-z][A-Za-z0-9_+-]*(?:\.[A-Za-z0-9][A-Za-z0-9_+-]*)+$') -or
                   ($id -cmatch '^[A-Z0-9]{8,16}$')
        if (-not $idValid -or $id -match '^(Name|Id|Version|Available|Source|winget|msstore)$' -or $id -match '^\d') { continue }

        $name = ''
        $version = ''
        $available = ''
        if ($idCol -gt 0 -and $line.Length -gt 0) {
            $nameEnd = [Math]::Min($idCol, $line.Length)
            $name = $line.Substring(0, $nameEnd).Trim()
        }
        if ($verCol -ge 0 -and $line.Length -gt $verCol) {
            $verEnd = $line.Length
            if ($availCol -gt $verCol) { $verEnd = [Math]::Min($availCol, $line.Length) }
            if ($verEnd -gt $verCol) { $version = $line.Substring($verCol, $verEnd - $verCol).Trim() }
        }
        if ($availCol -ge 0 -and $line.Length -gt $availCol) {
            $avEnd = $line.Length
            if ($srcCol -gt $availCol) { $avEnd = [Math]::Min($srcCol, $line.Length) }
            if ($avEnd -gt $availCol) { $available = $line.Substring($availCol, $avEnd - $availCol).Trim() }
        }

        $dest = $bulk
        if ($section -eq 'explicit') { $dest = $explicit }
        elseif ($section -eq 'unknown') { $dest = $unknown }
        if (-not $dest.Contains($id)) {
            [void]$dest.Add($id)
            [void]$rows.Add([pscustomobject]@{
                Name      = $name
                Id        = $id
                Version   = $version
                Available = $available
                Section   = $section
            })
        }
    }
    return [pscustomobject]@{
        Bulk     = [string[]]@($bulk.ToArray())
        Explicit = [string[]]@($explicit.ToArray())
        Unknown  = [string[]]@($unknown.ToArray())
        Rows     = @($rows.ToArray())
    }
}

function Get-WingetUpgradeOutcome {
    param([string]$Text, $ExitCode = 0)
    if ($Text -match '(?i)Successfully (installed|upgraded)') { return 'Upgraded' }
    if ($Text -match '(?i)No applicable upgrade|No newer package versions|No installed package found matching') { return 'Current' }
    if ($Text -match '(?i)interactive|user interaction|does not support silent|requires .+ interaction|cannot be run silently') { return 'NeedsInteraction' }
    $code = 0
    try { $code = [int]$ExitCode } catch { $code = 0 }
    if ($code -ne 0) { return 'Failed' }
    if ($Text -match '(?i)installer failed|installation failed|failed to install|exit code') { return 'Failed' }
    return 'Finished'
}

function Format-WingetUpgradeLabel {
    param($Choice)
    $name = ''
    if ($Choice -and $Choice.Name) { $name = [string]$Choice.Name.Trim() }
    if (-not $name -and $Choice) { $name = [string]$Choice.Id }
    $label = $name
    if ($Choice -and $Choice.Id -and ([string]$Choice.Id) -ne $name) {
        $label = ("{0}   {1}" -f $name, $Choice.Id)
    }
    $from = ''
    $to = ''
    if ($Choice) {
        $from = [string]$Choice.Version
        $to = [string]$Choice.Available
    }
    if ($from -and $to) {
        $label = ("{0}   {1} -> {2}" -f $label, $from, $to)
    } elseif ($to) {
        $label = ("{0}   -> {1}" -f $label, $to)
    }
    if ($Choice -and $Choice.Section -eq 'explicit') {
        $label = ("{0}   (direct)" -f $label)
    }
    return $label
}

function Get-WingetUpgradeChoices {
    param(
        $Rows,
        $BulkIds,
        $ExplicitIds
    )
    $byKey = @{}
    foreach ($row in @($Rows)) {
        if (-not $row -or -not $row.Id) { continue }
        $key = ('{0}|{1}' -f $row.Section, $row.Id)
        if (-not $byKey.ContainsKey($key)) { $byKey[$key] = $row }
    }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($pair in @(
        @{ Section = 'bulk'; Ids = @($BulkIds) },
        @{ Section = 'explicit'; Ids = @($ExplicitIds) }
    )) {
        foreach ($id in @($pair.Ids)) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $key = ('{0}|{1}' -f $pair.Section, $id)
            $row = $null
            if ($byKey.ContainsKey($key)) { $row = $byKey[$key] }
            $name = ''
            $version = ''
            $available = ''
            if ($row) {
                $name = [string]$row.Name
                $version = [string]$row.Version
                $available = [string]$row.Available
            }
            [void]$list.Add([pscustomobject]@{
                Name      = $name
                Id        = [string]$id
                Version   = $version
                Available = $available
                Section   = [string]$pair.Section
            })
        }
    }
    return @($list.ToArray())
}

function Split-WingetUpgradeSelection {
    param(
        $BulkIds,
        $ExplicitIds,
        $SelectedIds
    )
    $selected = @{}
    foreach ($id in @($SelectedIds)) {
        if ($id) { $selected[[string]$id] = $true }
    }
    $selBulk = New-Object System.Collections.Generic.List[string]
    $exBulk = New-Object System.Collections.Generic.List[string]
    $selExplicit = New-Object System.Collections.Generic.List[string]
    foreach ($id in @($BulkIds)) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($selected.ContainsKey([string]$id)) { [void]$selBulk.Add([string]$id) }
        else { [void]$exBulk.Add([string]$id) }
    }
    foreach ($id in @($ExplicitIds)) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($selected.ContainsKey([string]$id)) { [void]$selExplicit.Add([string]$id) }
    }
    return [pscustomobject]@{
        Bulk         = [string[]]@($selBulk.ToArray())
        ExcludedBulk = [string[]]@($exBulk.ToArray())
        Explicit     = [string[]]@($selExplicit.ToArray())
    }
}

function Read-WingetPackageSelection {
    param(
        [object[]]$Choices,
        [string]$Note = ''
    )
    $choicesLocal = @($Choices | Where-Object { $_ -and $_.Id })
    $count = $choicesLocal.Count
    if ($count -eq 0) { return @() }
    $checked = New-Object 'bool[]' $count
    for ($i = 0; $i -lt $count; $i++) { $checked[$i] = $true }
    while ($true) {
        Write-Host ""
        Write-Host "  Choose winget apps to update"
        Write-Host "  Checked apps are updated. Unchecked apps are left as they are."
        if ($Note) {
            foreach ($noteLine in ($Note -split "`r?`n")) {
                if ($noteLine.Trim()) { Write-Host ("  {0}" -f $noteLine.Trim()) }
            }
        }
        Write-Host ""
        for ($i = 0; $i -lt $count; $i++) {
            $mark = ' '
            if ($checked[$i]) { $mark = 'x' }
            Write-Host ("  [{0}] {1,2}. {2}" -f $mark, ($i + 1), (Format-WingetUpgradeLabel $choicesLocal[$i]))
        }
        Write-Host ""
        Write-Host "  Number toggles a row. A = all, N = none, U = update, Q = cancel"
        $ans = Read-Host "  Choice"
        if ($null -eq $ans) { return $null }
        $trim = $ans.Trim()
        if ($trim -match '^(?i)q$') { return $null }
        if ($trim -match '^(?i)u$') {
            $ids = New-Object System.Collections.Generic.List[string]
            for ($i = 0; $i -lt $count; $i++) {
                if ($checked[$i]) { [void]$ids.Add([string]$choicesLocal[$i].Id) }
            }
            if ($ids.Count -eq 0) {
                Write-Host "  Check at least one app, or Q to cancel." -ForegroundColor Yellow
                continue
            }
            return [string[]]@($ids.ToArray())
        }
        if ($trim -match '^(?i)a$') {
            for ($i = 0; $i -lt $count; $i++) { $checked[$i] = $true }
            continue
        }
        if ($trim -match '^(?i)n$') {
            for ($i = 0; $i -lt $count; $i++) { $checked[$i] = $false }
            continue
        }
        $n = 0
        $partsOk = $true
        $any = $false
        foreach ($part in ($trim -split '[,\s]+')) {
            if (-not $part) { continue }
            $any = $true
            if (-not [int]::TryParse($part, [ref]$n) -or $n -lt 1 -or $n -gt $count) {
                $partsOk = $false
                break
            }
        }
        if (-not $any -or -not $partsOk) {
            Write-Host "  Enter a row number, A, N, U, or Q." -ForegroundColor Yellow
            continue
        }
        foreach ($part in ($trim -split '[,\s]+')) {
            if (-not $part) { continue }
            [void][int]::TryParse($part, [ref]$n)
            $checked[$n - 1] = -not $checked[$n - 1]
        }
    }
}

function Show-WingetPackagePickerForm {
    param(
        [object[]]$Choices,
        [string]$Note = ''
    )
    Add-Type -AssemblyName System.Windows.Forms -EA Stop
    Add-Type -AssemblyName System.Drawing -EA Stop
    $choicesLocal = @($Choices | Where-Object { $_ -and $_.Id })
    $bg = [System.Drawing.Color]::FromArgb(15, 15, 27)
    $panel = [System.Drawing.Color]::FromArgb(26, 26, 46)
    $textColor = [System.Drawing.Color]::White
    $muted = [System.Drawing.Color]::FromArgb(165, 165, 197)
    $accent = [System.Drawing.Color]::FromArgb(0, 180, 216)
    $ghost = [System.Drawing.Color]::FromArgb(20, 20, 36)
    try {
        $theme = $null
        if ($Script:Theme) { $theme = $Script:Theme }
        elseif (Get-Command Get-GuiTheme -EA SilentlyContinue) { $theme = Get-GuiTheme }
        if ($theme) {
            $bg = $theme.Bg
            $panel = $theme.Panel
            $textColor = $theme.Text
            $muted = $theme.Muted
            $accent = $theme.Accent
            if ($theme.BtnGhost) { $ghost = $theme.BtnGhost }
        }
    } catch { }

    return Invoke-WithUiModal {
        $form = $null
        try {
            $form = New-Object System.Windows.Forms.Form
            $form.Text = "Choose winget upgrades"
            $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $form.MaximizeBox = $false
            $form.MinimizeBox = $false
            $form.ShowInTaskbar = $false
            $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
            $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
            $form.ClientSize = New-Object System.Drawing.Size(680, 520)
            $form.BackColor = $bg
            $form.ForeColor = $textColor
            $form.Tag = $null
            $pickerRows = @($choicesLocal)

            $title = New-Object System.Windows.Forms.Label
            $title.Text = "Choose apps to update"
            $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
            $title.ForeColor = $textColor
            $title.BackColor = $bg
            $title.AutoSize = $false
            $title.Location = New-Object System.Drawing.Point(20, 16)
            $title.Size = New-Object System.Drawing.Size(640, 28)
            $form.Controls.Add($title)

            $hint = New-Object System.Windows.Forms.Label
            $hint.Text = "Check the apps you want to update. Everything starts checked."
            $hint.ForeColor = $muted
            $hint.BackColor = $bg
            $hint.AutoSize = $false
            $hint.Location = New-Object System.Drawing.Point(20, 46)
            $hint.Size = New-Object System.Drawing.Size(640, 36)
            $form.Controls.Add($hint)

            $list = New-Object System.Windows.Forms.CheckedListBox
            $list.Font = New-Object System.Drawing.Font('Segoe UI', 10)
            $list.BackColor = $panel
            $list.ForeColor = $textColor
            $list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $list.CheckOnClick = $true
            $list.IntegralHeight = $false
            $list.HorizontalScrollbar = $true
            $list.Location = New-Object System.Drawing.Point(20, 90)
            $list.Size = New-Object System.Drawing.Size(640, 300)
            foreach ($choice in $pickerRows) {
                [void]$list.Items.Add((Format-WingetUpgradeLabel $choice))
            }
            for ($i = 0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i, $true) }
            $form.Controls.Add($list)

            $noteLbl = New-Object System.Windows.Forms.Label
            $noteLbl.Text = $Note
            $noteLbl.ForeColor = $muted
            $noteLbl.BackColor = $bg
            $noteLbl.AutoSize = $false
            $noteLbl.Location = New-Object System.Drawing.Point(20, 398)
            $noteLbl.Size = New-Object System.Drawing.Size(640, 52)
            $noteLbl.Visible = -not [string]::IsNullOrWhiteSpace($Note)
            $form.Controls.Add($noteLbl)
            if (-not $noteLbl.Visible) { $list.Height = 348 }

            $btnAll = New-Object System.Windows.Forms.Button
            $btnAll.Text = "All"
            $btnAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnAll.FlatAppearance.BorderSize = 0
            $btnAll.BackColor = $ghost
            $btnAll.ForeColor = $textColor
            $btnAll.Location = New-Object System.Drawing.Point(20, 460)
            $btnAll.Size = New-Object System.Drawing.Size(88, 36)
            $form.Controls.Add($btnAll)

            $btnNone = New-Object System.Windows.Forms.Button
            $btnNone.Text = "None"
            $btnNone.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnNone.FlatAppearance.BorderSize = 0
            $btnNone.BackColor = $ghost
            $btnNone.ForeColor = $textColor
            $btnNone.Location = New-Object System.Drawing.Point(116, 460)
            $btnNone.Size = New-Object System.Drawing.Size(88, 36)
            $form.Controls.Add($btnNone)

            $btnCancel = New-Object System.Windows.Forms.Button
            $btnCancel.Text = "Cancel"
            $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnCancel.FlatAppearance.BorderSize = 0
            $btnCancel.BackColor = $ghost
            $btnCancel.ForeColor = $textColor
            $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $btnCancel.Location = New-Object System.Drawing.Point(392, 460)
            $btnCancel.Size = New-Object System.Drawing.Size(120, 36)
            $form.Controls.Add($btnCancel)
            $form.CancelButton = $btnCancel

            $btnOk = New-Object System.Windows.Forms.Button
            $btnOk.Text = ("Update ({0})" -f $list.Items.Count)
            $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnOk.FlatAppearance.BorderSize = 0
            $btnOk.BackColor = $accent
            $btnOk.ForeColor = [System.Drawing.Color]::White
            $btnOk.Location = New-Object System.Drawing.Point(520, 460)
            $btnOk.Size = New-Object System.Drawing.Size(140, 36)
            $form.Controls.Add($btnOk)
            $form.AcceptButton = $btnOk

            $btnAll.Add_Click({
                for ($n = 0; $n -lt $list.Items.Count; $n++) { $list.SetItemChecked($n, $true) }
                $btnOk.Text = ("Update ({0})" -f $list.Items.Count)
            }.GetNewClosure())
            $btnNone.Add_Click({
                for ($n = 0; $n -lt $list.Items.Count; $n++) { $list.SetItemChecked($n, $false) }
                $btnOk.Text = "Update (0)"
            }.GetNewClosure())
            $list.Add_ItemCheck({
                param($sender, $e)
                $n = 0
                for ($i = 0; $i -lt $sender.Items.Count; $i++) {
                    $on = $sender.GetItemChecked($i)
                    if ($i -eq $e.Index) {
                        $on = ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked)
                    }
                    if ($on) { $n++ }
                }
                $btnOk.Text = ("Update ({0})" -f $n)
            }.GetNewClosure())
            $btnOk.Add_Click({
                $ids = New-Object System.Collections.Generic.List[string]
                for ($n = 0; $n -lt $list.Items.Count; $n++) {
                    if ($list.GetItemChecked($n)) { [void]$ids.Add([string]$pickerRows[$n].Id) }
                }
                if ($ids.Count -eq 0) {
                    $hint.Text = "Check at least one app, or Cancel to skip updates."
                    return
                }
                $form.Tag = [string[]]@($ids.ToArray())
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            }.GetNewClosure())

            $owner = $null
            try { $owner = Get-UiControl Form } catch { }
            if ($owner -and -not $owner.IsDisposed) {
                $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
                [void]$form.ShowDialog($owner)
            } else {
                [void]$form.ShowDialog()
            }
            $pickedTag = $form.Tag
            return $pickedTag
        } finally {
            if ($form) {
                try { $form.Dispose() } catch { }
            }
        }
    }
}

function Show-WingetPackagePicker {
    param(
        [object[]]$Choices,
        [string]$Note = ''
    )
    $choicesLocal = @($Choices | Where-Object { $_ -and $_.Id })
    if ($choicesLocal.Count -eq 0) { return @() }
    $opened = $false
    $picked = $null
    try {
        $picked = Show-WingetPackagePickerForm -Choices $choicesLocal -Note $Note
        $opened = $true
    } catch {
        Write-Warn ("Could not open the app list: {0}" -f $_.Exception.Message)
    }
    if ($opened) { return $picked }
    return Read-WingetPackageSelection -Choices $choicesLocal -Note $Note
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

        # Always parse. "No newer package versions" can sit above an explicit-targeting
        # table (Unity editors). Returning early there hid those apps with no message.
        $parsed = ConvertFrom-WingetUpgradeList -Text $listOut
        $packageIds = [System.Collections.Generic.List[string]]::new()
        $explicitIds = [System.Collections.Generic.List[string]]::new()
        $unknownIds = [System.Collections.Generic.List[string]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in @(
            @{ Ids = @($parsed.Bulk); Dest = $packageIds },
            @{ Ids = @($parsed.Explicit); Dest = $explicitIds },
            @{ Ids = @($parsed.Unknown); Dest = $unknownIds }
        )) {
            foreach ($id in @($entry.Ids)) {
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                $skip = $false
                foreach ($s in $wingetSkipIds) {
                    if ($id -ieq $s) { $skip = $true; break }
                }
                if ($skip) {
                    if (-not ($skipped -contains $id)) { [void]$skipped.Add($id) }
                    continue
                }
                if (-not $entry.Dest.Contains($id)) { [void]$entry.Dest.Add($id) }
            }
        }
        if ($skipped.Count -gt 0) {
            Write-Info ("Skipping self-updating apps: {0}" -f (($skipped | Select-Object -Unique) -join ", "))
        }
        if ($unknownIds.Count -gt 0) {
            Write-Warn ("Not upgraded (winget cannot tell the installed version, so a silent upgrade is unsafe): {0}" -f ($unknownIds -join ", "))
        }
        if ($explicitIds.Count -gt 0) {
            Write-Info ("Need a direct upgrade (winget leaves these out of upgrade --all): {0}" -f ($explicitIds -join ", "))
        }

        $countFromFooter = 0
        if ($listOut -match '(\d+)\s+upgrades?\s+available') { $countFromFooter = [int]$Matches[1] }
        $count = $packageIds.Count
        if ($count -eq 0 -and $explicitIds.Count -eq 0) {
            if ($listOut -match '(?i)explicit targeting' -and $explicitIds.Count -eq 0) {
                Write-Warn "winget listed packages that need a direct upgrade, but their Ids could not be read. Nothing was changed."
                return
            }
            if ($skipped.Count -gt 0 -or $unknownIds.Count -gt 0) {
                Write-Ok "winget bulk list is clear (see notes above for anything left out)"
                return
            }
            if ($listOut -match '(?i)cannot be determined') {
                Write-Warn "winget hid one or more apps because it cannot tell the installed version. They were not upgraded."
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

        Write-Info ("Found {0} bulk upgrade(s): {1}" -f $count, $(if ($count) { $packageIds -join ", " } else { "(none)" }))
        $choices = @(Get-WingetUpgradeChoices -Rows $parsed.Rows -BulkIds @($packageIds) -ExplicitIds @($explicitIds))
        $pickerNotes = New-Object System.Collections.Generic.List[string]
        if ($skipped.Count -gt 0) {
            [void]$pickerNotes.Add(("Already skipped (they update themselves): {0}" -f (($skipped | Select-Object -Unique) -join ", ")))
        }
        if ($unknownIds.Count -gt 0) {
            [void]$pickerNotes.Add(("Not listed (version unknown): {0}" -f ($unknownIds -join ", ")))
        }
        $pickerNote = [string]::Join("`n", [string[]]@($pickerNotes.ToArray()))
        $selectedIds = $null
        if ($Script:HeadlessRun) {
            # Saved HomeWinget is the opt-in. A hidden Sunday task cannot wait on a dialog.
            Write-Info "Scheduled run: winget upgrades were saved on, so they run without a prompt."
            $selectedIds = @($choices | ForEach-Object { [string]$_.Id })
        } else {
            $selectedIds = Show-WingetPackagePicker -Choices $choices -Note $pickerNote
        }
        if ($null -eq $selectedIds) {
            Write-Warn "winget upgrades skipped by user"
            return
        }
        $split = Split-WingetUpgradeSelection -BulkIds @($packageIds) -ExplicitIds @($explicitIds) -SelectedIds @($selectedIds)
        $packageIds = [System.Collections.Generic.List[string]]::new()
        $explicitIds = [System.Collections.Generic.List[string]]::new()
        $excludedBulkIds = [System.Collections.Generic.List[string]]::new()
        foreach ($id in @($split.Bulk)) { if ($id) { [void]$packageIds.Add([string]$id) } }
        foreach ($id in @($split.Explicit)) { if ($id) { [void]$explicitIds.Add([string]$id) } }
        foreach ($id in @($split.ExcludedBulk)) { if ($id) { [void]$excludedBulkIds.Add([string]$id) } }
        if ($packageIds.Count -eq 0 -and $explicitIds.Count -eq 0) {
            Write-Warn "winget upgrades skipped by user"
            return
        }
        $selectedSet = @{}
        foreach ($id in @($packageIds)) { $selectedSet[[string]$id] = $true }
        foreach ($id in @($explicitIds)) { $selectedSet[[string]$id] = $true }
        $chosenNames = New-Object System.Collections.Generic.List[string]
        $leftNames = New-Object System.Collections.Generic.List[string]
        foreach ($c in @($choices)) {
            $label = if ($c.Name) { [string]$c.Name } else { [string]$c.Id }
            if ($selectedSet.ContainsKey([string]$c.Id)) { [void]$chosenNames.Add($label) }
            else { [void]$leftNames.Add($label) }
        }
        Write-Info ("Updating {0} selected app(s): {1}" -f $chosenNames.Count, ($chosenNames -join ", "))
        if ($leftNames.Count -gt 0) {
            Write-Info ("Left unchecked: {0}" -f ($leftNames -join ", "))
        }

        Assert-NotCancelled
        if ($packageIds.Count -gt 0 -and $excludedBulkIds.Count -eq 0) {
            Write-Info "Upgrading every listed app in one silent winget pass. App updaters are not opened one by one."
        } elseif ($packageIds.Count -gt 0) {
            Write-Info ("Upgrading {0} selected app(s) silently. Unchecked apps are not installed." -f $packageIds.Count)
        }
        if ($explicitIds.Count -gt 0) {
            Write-Info "Direct silent upgrades for selected packages winget excludes from --all."
        }
        # Only pin self-updaters that actually showed up, and only for the all-checked
        # pass. Pinning the whole skip list, then upgrading each id, is what made a
        # long queue open installer after installer. A partial selection does not use
        # "upgrade --all", so an unchecked app cannot be included.
        $skippedJoined = [string]::Join("`n", [string[]]@($skipped))
        $explicitJoined = [string]::Join("`n", [string[]]@($explicitIds))
        $excludedJoined = [string]::Join("`n", [string[]]@($excludedBulkIds))
        $selectedBulkJoined = [string]::Join("`n", [string[]]@($packageIds))
        $bulkCount = $packageIds.Count
        $outObj = Invoke-WithUiWait -Activity "winget upgrade" -TimeoutSec 3600 -LeaveRunning -ArgumentList @($winget, $skippedJoined, $explicitJoined, $bulkCount, $excludedJoined, $selectedBulkJoined) -ScriptBlock {
            param([string]$WingetPath, [string]$SkippedJoined, [string]$ExplicitJoined, [int]$BulkCount, [string]$ExcludedJoined, [string]$SelectedBulkJoined)
            $mustPin = @()
            if ($SkippedJoined -and $SkippedJoined.Trim()) {
                $mustPin = @($SkippedJoined -split "`n" | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
            }
            $excluded = @()
            if ($ExcludedJoined -and $ExcludedJoined.Trim()) {
                $excluded = @($ExcludedJoined -split "`n" | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
            }
            $selectedBulk = @()
            if ($SelectedBulkJoined -and $SelectedBulkJoined.Trim()) {
                $selectedBulk = @($SelectedBulkJoined -split "`n" | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
            }

            $addedPins = New-Object System.Collections.Generic.List[string]
            $pinFailed = New-Object System.Collections.Generic.List[string]
            $useBulk = ($BulkCount -gt 0 -and $excluded.Count -eq 0)
            try {
                if ($useBulk -and $mustPin.Count -gt 0) {
                    $pinList = & $WingetPath pin list --disable-interactivity 2>&1 | Out-String
                    foreach ($s in $mustPin) {
                        if ($pinList -and ($pinList -match [regex]::Escape($s))) { continue }
                        $pinOut = & $WingetPath pin add --id $s --exact --blocking --disable-interactivity --accept-source-agreements 2>&1 | Out-String
                        $pinOk = ($LASTEXITCODE -eq 0) -or ($pinOut -match '(?i)pin added|already exists|already pinned')
                        if ($pinOk) { [void]$addedPins.Add($s) } else { [void]$pinFailed.Add($s) }
                    }
                }

                # One process when every normal-list app is checked.
                # A partial selection upgrades only those ids, so unchecked apps stay put.
                $bulkText = ''
                $bulkExit = 0
                $ok = 0
                $fail = 0
                $modeName = 'Direct'
                $direct = New-Object System.Collections.Generic.List[object]
                if ($useBulk) {
                    $modeName = 'Bulk'
                    $bulkText = & $WingetPath upgrade --all --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
                    $bulkExit = $LASTEXITCODE
                    $ok = ([regex]::Matches($bulkText, '(?i)Successfully (installed|upgraded)')).Count
                    $fail = ([regex]::Matches($bulkText, '(?i)installation failed|installer failed|failed to install|Installer failed')).Count
                } elseif ($BulkCount -gt 0) {
                    $modeName = 'Selected'
                    foreach ($id in $selectedBulk) {
                        $text = & $WingetPath upgrade --id $id --exact --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
                        [void]$direct.Add([pscustomobject]@{
                            Id       = $id
                            Output   = $text
                            ExitCode = $LASTEXITCODE
                            Kind     = 'selected'
                        })
                    }
                }
                $explicitIdsLocal = @()
                if ($ExplicitJoined -and $ExplicitJoined.Trim()) {
                    $explicitIdsLocal = @($ExplicitJoined -split "`n" | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
                }
                foreach ($id in $explicitIdsLocal) {
                    $text = & $WingetPath upgrade --id $id --exact --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
                    [void]$direct.Add([pscustomobject]@{
                        Id       = $id
                        Output   = $text
                        ExitCode = $LASTEXITCODE
                        Kind     = 'explicit'
                    })
                }
                if ($modeName -eq 'Selected') {
                    $note = 'Selected apps were upgraded on their own so unchecked apps were not included'
                } elseif ($modeName -eq 'Bulk') {
                    $note = 'One silent winget pass for the normal list'
                } else {
                    $note = 'No normal-list apps were selected'
                }
                if ($explicitIdsLocal.Count -gt 0) {
                    $note += ('. Direct upgrades: ' + ($explicitIdsLocal -join ', '))
                }
                if ($pinFailed.Count -gt 0) {
                    $note += ('. Could not pin self-updaters: ' + ($pinFailed -join ', '))
                }
                $failCount = $fail
                if ($modeName -eq 'Bulk' -and $BulkCount -gt 0 -and $bulkExit -ne 0 -and $failCount -eq 0 -and $ok -eq 0 -and $bulkText -notmatch 'No applicable upgrade|No newer package versions|No installed package found matching input criteria') {
                    $failCount = 1
                }
                return [pscustomobject]@{
                    Mode        = $modeName
                    Output      = $bulkText
                    OkCount     = $ok
                    FailCount   = $failCount
                    OkIds       = ''
                    FailIds     = ''
                    Note        = $note
                    BulkSkipped = $false
                    Direct      = @($direct.ToArray())
                }
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
        $bulkSkipped = $false
        try {
            $out = [string]$outPayload.Output
            $okCount = [int]$outPayload.OkCount
            $failCount = [int]$outPayload.FailCount
            $failIds = [string]$outPayload.FailIds
            try { $mode = [string]$outPayload.Mode } catch { }
            try { $note = [string]$outPayload.Note } catch { }
            try { $bulkSkipped = [bool]$outPayload.BulkSkipped } catch { }
        } catch {
            $out = Get-AsyncResultText $outObj
            $okCount = ([regex]::Matches($out, '(?i)Successfully (installed|upgraded)')).Count
        }

        if ($note) {
            if ($bulkSkipped) { Write-Warn $note } else { Write-Info $note }
        }
        if ($mode -eq 'Bulk' -and $okCount -eq 0 -and $failCount -eq 0 -and $packageIds.Count -gt 0) {
            Write-Ok "winget bulk upgrade finished (apps current or already newest)"
        } elseif ($okCount -gt 0) {
            Write-Ok ("winget upgraded {0} package(s) in the silent pass" -f $okCount)
        }
        if ($failCount -gt 0) {
            Write-Warn ("winget bulk pass reported {0} failure(s): {1}" -f $failCount, $(if ($failIds) { $failIds } else { "see the activity panel" }))
        }
        $directResults = @()
        try { $directResults = @($outPayload.Direct) } catch { $directResults = @() }
        foreach ($d in $directResults) {
            if (-not $d -or -not $d.Id) { continue }
            $kind = ''
            try { $kind = [string]$d.Kind } catch { }
            $outcome = Get-WingetUpgradeOutcome -Text ([string]$d.Output) -ExitCode $d.ExitCode
            switch ($outcome) {
                'Upgraded' {
                    if ($kind -eq 'selected') { Write-Ok ("{0} upgraded" -f $d.Id) }
                    else { Write-Ok ("{0} upgraded (direct, because winget excludes it from upgrade --all)" -f $d.Id) }
                }
                'Current'  { Write-Ok ("{0} is already current" -f $d.Id) }
                'NeedsInteraction' {
                    Write-Warn ("{0} was not upgraded. Its installer has no silent mode, so no updater window was opened." -f $d.Id)
                    Write-Info ("Update it from the app, or run: winget upgrade --id {0}" -f $d.Id)
                }
                'Finished' {
                    if ($kind -eq 'selected') { Write-Ok ("{0} upgrade finished" -f $d.Id) }
                    else { Write-Ok ("{0} direct upgrade finished" -f $d.Id) }
                }
                default {
                    Write-Warn ("{0} was not upgraded." -f $d.Id)
                    $detail = ([string]$d.Output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
                    if ($detail) { Write-Info $detail.Trim() }
                }
            }
        }
        if ($okCount -eq 0 -and $failCount -eq 0 -and $mode -ne 'Bulk' -and $directResults.Count -eq 0) {
            Write-Ok "winget apps are up to date"
        } elseif ($okCount -eq 0 -and $failCount -gt 0 -and $directResults.Count -eq 0) {
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
        if ([string]::IsNullOrWhiteSpace($p) -or -not (Test-Path -LiteralPath $p)) { continue }
        Write-Info ("Scanning {0}" -f $p)
        Pump-Ui
        $freed = Remove-OldFilesInPath -Path $p -OlderThanDays 0 -DeleteFoldersToo
        $total += $freed
        if ($freed -gt 0) {
            Write-Ok ("{0}: freed {1}" -f (Split-Path $p -Leaf), (Format-UiByteSize $freed))
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
        # Path.Combine('C:', 'Users') is the drive-relative path 'C:Users', not 'C:\Users'.
        $base = $Base.Trim()
        if ($base -match '^[A-Za-z]:\\?$') {
            $base = $base.TrimEnd('\') + '\'
        } else {
            $base = $base.TrimEnd('\', '/')
        }
        $child = $Child
        if ($child -and $base.EndsWith('\') -and ($child.StartsWith('\') -or $child.StartsWith('/'))) {
            $child = $child.TrimStart('\', '/')
        }
        return [System.IO.Path]::Combine($base, $child)
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

function Write-HeadlessRunLog {
    param([string]$Summary)
    $dir = Join-Path $env:LOCALAPPDATA 'PC-Maintenance-Kit'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $path = Join-Path $dir 'scheduled-last-run.log'
    $body = @(
        ("==== {0:yyyy-MM-dd HH:mm:ss} ====" -f (Get-Date)),
        $Summary
    ) -join "`r`n"
    Set-Content -LiteralPath $path -Value $body -Encoding UTF8
    Write-Info ("Headless summary saved to {0}" -f $path)
    return $path
}

function Get-LastScheduledRunSummary {
    $path = Join-Path (Join-Path $env:LOCALAPPDATA 'PC-Maintenance-Kit') 'scheduled-last-run.log'
    if (-not (Test-Path -LiteralPath $path)) { return 'No weekly run recorded yet.' }
    try {
        $raw = [System.IO.File]::ReadAllText($path)
    } catch {
        return 'Could not read the last weekly run.'
    }
    $flat = ($raw -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($flat)) { return 'No weekly run recorded yet.' }
    if ($flat.Length -gt 220) { $flat = $flat.Substring(0, 220).Trim() + '...' }
    return $flat
}

function Show-RebootRecommendedDialog {
    if (-not (Test-RebootPending)) { return }
    if ($Script:HeadlessRun) {
        Write-Warn "A restart is pending. Scheduled run will not prompt."
        return
    }
    try {
        [void](Show-UiMessageBox `
            -Text "Windows has a pending restart (often after updates).`n`nRestart when you finish gaming for best stability." `
            -Caption "PC Maintenance - Restart recommended" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Information))
    } catch { }
}

function ConvertTo-DiskHealthName {
    param($Value)
    if ($null -eq $Value) { return 'Unknown' }
    $text = [string]$Value
    if ($text -match 'Healthy|Warning|Unhealthy') { return $text }
    switch ($text) {
        '0' { return 'Healthy' }
        '1' { return 'Warning' }
        '2' { return 'Unhealthy' }
        default { return $text }
    }
}

function ConvertTo-DiskMediaName {
    param($Value)
    if ($null -eq $Value) { return 'Unspecified' }
    $text = [string]$Value
    if ($text -match 'SSD|HDD|SCM|Unspecified') { return $text }
    switch ($text) {
        '3' { return 'HDD' }
        '4' { return 'SSD' }
        '5' { return 'SCM' }
        default { return 'Unspecified' }
    }
}

function Get-SystemDisk {
    param([switch]$Refresh)
    # Hardware identity barely changes during a session. A short cache made every
    # panel refresh after winget reload the Storage module and freeze the window.
    if (-not $Refresh -and $null -ne $Script:SystemDiskCache -and (([datetime]::UtcNow - $Script:SystemDiskCacheUtc).TotalSeconds -lt 600)) {
        return $Script:SystemDiskCache
    }
    $phys = $null
    try {
        # CIM avoids Import-Module Storage, which is what made the first scan feel stuck.
        $part = @(Get-CimInstance -Namespace root\microsoft\windows\storage -ClassName MSFT_Partition -EA Stop |
            Where-Object { $_.DriveLetter -eq 67 -or [string]$_.DriveLetter -eq 'C' } |
            Select-Object -First 1)
        $disk = $null
        if ($part) {
            $disk = @(Get-CimInstance -Namespace root\microsoft\windows\storage -ClassName MSFT_PhysicalDisk -EA Stop |
                Where-Object { [string]$_.DeviceId -eq [string]$part[0].DiskNumber } |
                Select-Object -First 1)
        }
        if ($disk) {
            $phys = [pscustomobject]@{
                FriendlyName = [string]$disk[0].FriendlyName
                HealthStatus = (ConvertTo-DiskHealthName $disk[0].HealthStatus)
                MediaType    = (ConvertTo-DiskMediaName $disk[0].MediaType)
            }
        }
    } catch { }
    if (-not $phys) {
        try {
            $partition = Get-Partition -DriveLetter C -EA Stop
            $raw = Get-PhysicalDisk -Number $partition.DiskNumber -EA SilentlyContinue
            if ($raw) {
                $phys = [pscustomobject]@{
                    FriendlyName = [string]$raw.FriendlyName
                    HealthStatus = (ConvertTo-DiskHealthName $raw.HealthStatus)
                    MediaType    = (ConvertTo-DiskMediaName $raw.MediaType)
                }
            }
        } catch { }
    }
    $Script:SystemDiskCache = $phys
    $Script:SystemDiskCacheUtc = [datetime]::UtcNow
    return $phys
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
            if ($Script:DoWinUpdate) {
                Write-Warn "Windows Update service was stopped - starting it for this update run"
                Start-Service wuauserv -EA SilentlyContinue
            } else {
                Write-Info "Windows Update service is stopped (left as-is)"
            }
        } else {
            Write-Ok "Windows Update service: Running"
        }
        if ($bits -and $bits.Status -ne 'Running') {
            if ($Script:DoWinUpdate) {
                Write-Warn "BITS service was stopped - starting it for this update run"
                Start-Service bits -EA SilentlyContinue
            } else {
                Write-Info "BITS service is stopped (left as-is)"
            }
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
                -Text ("{0}`n`nThis can take 15-60+ minutes and may require a restart.`nA restore point is recommended.`n`nStop skips steps that have not started. DISM or SFC that has already started keeps running until Windows finishes it.`n`nContinue?" -f $label) `
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
    Write-Host "  Stop skips steps that have not started. DISM or SFC already running is left to finish." -ForegroundColor DarkGray
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
        Register-TrackedProcess $p -LeaveRunning
        $spin = @('|','/','-','\'); $i = 0
        $lastHbSec = -15
        $notedStop = $false
        while (-not $p.HasExited) {
            if (Test-CancelRequested -and -not $notedStop) {
                $notedStop = $true
                Write-Warn "Stop will not kill DISM. It keeps running until Windows finishes. SFC is skipped after that."
            }
            $sec = [int]((Get-Date) - $p.StartTime).TotalSeconds
            Write-Host -NoNewline ("`r  [{0}] DISM running... {1}s   " -f $spin[$i % 4], $sec) -ForegroundColor DarkYellow
            Set-UiStatusText -Text ("[{0}] DISM running... {1}s" -f $spin[$i % 4], $sec)
            if (($sec - $lastHbSec) -ge 15) {
                $lastHbSec = $sec
                Write-Info ("DISM still running... {0}s (Stop skips later steps)" -f $sec)
            }
            Pump-Ui
            Start-Sleep -Milliseconds 400
            $i++
        }
        Write-Host ""
        $null = $p.WaitForExit(1000)
        $code = $p.ExitCode
        if ($code -eq 0) {
            Write-Ok "DISM completed successfully"
        } else {
            $shown = if ($null -eq $code) { 'unknown' } else { $code }
            Write-Warn "DISM exit code $shown - see $dismLog"
        }
        if (Test-CancelRequested) {
            Write-Warn "DISM finished after Stop. SFC was not started."
            return
        }
    } catch {
        if ($_.Exception.Message -match 'Cancelled') { throw }
        Write-Fail "DISM failed: $($_.Exception.Message)"
    }

    Assert-NotCancelled
    try {
        Write-Info "SFC /scannow starting..."
        $p = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -PassThru -NoNewWindow
        Register-TrackedProcess $p -LeaveRunning
        $spin = @('|','/','-','\'); $i = 0
        $lastHbSec = -15
        $notedStop = $false
        while (-not $p.HasExited) {
            if (Test-CancelRequested -and -not $notedStop) {
                $notedStop = $true
                Write-Warn "Stop will not kill SFC. It keeps running until Windows finishes."
            }
            $sec = [int]((Get-Date) - $p.StartTime).TotalSeconds
            Write-Host -NoNewline ("`r  [{0}] SFC running... {1}s   " -f $spin[$i % 4], $sec) -ForegroundColor DarkYellow
            Set-UiStatusText -Text ("[{0}] SFC running... {1}s" -f $spin[$i % 4], $sec)
            if (($sec - $lastHbSec) -ge 15) {
                $lastHbSec = $sec
                Write-Info ("SFC still running... {0}s (Stop leaves SFC running)" -f $sec)
            }
            Pump-Ui
            Start-Sleep -Milliseconds 400
            $i++
        }
        Write-Host ""
        $null = $p.WaitForExit(1000)
        $code = $p.ExitCode
        if ($code -eq 0) {
            Write-Ok "SFC finished successfully"
        } else {
            $shown = if ($null -eq $code) { 'unknown' } else { $code }
            Write-Warn "SFC finished with exit $shown - see CBS.log if issues persist"
        }
    } catch {
        if ($_.Exception.Message -match 'Cancelled') { throw }
        Write-Fail "SFC failed: $($_.Exception.Message)"
    }
}

function Get-RunSummaryText {
    $Script:EndFree = Get-CFreeGB -Refresh
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
    $Script:StartFree = Get-CFreeGB -Refresh

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
    if ($Script:HeadlessRun) {
        if (Test-RebootPending) {
            Write-Warn "A restart is pending. Scheduled run will not prompt."
        }
        $flagLine = ("Flags: cleanup=on restore={0} shaders={1} gaming={2} windows-update={3} winget={4} repair=off cache-wipe=off" -f `
            [bool]$Script:DoRestorePoint, [bool]$Script:DoShaderCleanup, [bool]$Script:DoGamingOptimize, `
            [bool]$Script:DoWinUpdate, [bool]$Script:DoWinget)
        $head = $flagLine
        if (Test-CancelRequested) { $head = "Stopped before every step finished.`r`n" + $head }
        Write-HeadlessRunLog -Summary ($head + "`r`n" + $summary)
    } elseif (-not (Test-CancelRequested)) {
        Show-RebootRecommendedDialog
        if (Get-Command Show-RunSummaryDialog -EA SilentlyContinue) {
            Show-RunSummaryDialog -Title "PC Maintenance - Summary" -Summary (Get-RunSummaryObject)
        }
    }
    Clear-TrackedProcesses
    return $summary
}
