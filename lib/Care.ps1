#Requires -Version 5.1
# Care presets + scheduled Weekly Full (Task Scheduler).

$Script:WeeklyCareTaskName = 'PC Maintenance Kit - Weekly Full'

function Get-CarePresetMap {
    return [ordered]@{
        Gamer = [ordered]@{
            HomeRestore = $true
            HomeShader  = $true
            HomeGaming  = $true
            HomeWU      = $false
            HomeWinget  = $false
            Label       = 'Gamer (safe weekly)'
        }
        Quiet = [ordered]@{
            HomeRestore = $false
            HomeShader  = $true
            HomeGaming  = $false
            HomeWU      = $false
            HomeWinget  = $false
            Label       = 'Quiet (cleanup only)'
        }
        Full = [ordered]@{
            HomeRestore = $true
            HomeShader  = $true
            HomeGaming  = $true
            HomeWU      = $true
            HomeWinget  = $true
            Label       = 'Full (includes updates)'
        }
    }
}

function Apply-CarePreset {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Gamer','Quiet','Full')]
        [string]$Name,
        $Controls
    )
    $map = Get-CarePresetMap
    $p = $map[$Name]
    if (-not $p) { return }
    if ($Controls -and $Controls.ChkHomeRestore) {
        $Controls.ChkHomeRestore.Checked = [bool]$p.HomeRestore
        $Controls.ChkHomeShader.Checked  = [bool]$p.HomeShader
        $Controls.ChkHomeGaming.Checked  = [bool]$p.HomeGaming
        $Controls.ChkHomeWU.Checked      = [bool]$p.HomeWU
        $Controls.ChkHomeWinget.Checked  = [bool]$p.HomeWinget
    }
    if ($Script:LoadedGuiSettings) {
        $Script:LoadedGuiSettings['CarePreset'] = $Name
        $Script:LoadedGuiSettings['HomeRestore'] = [bool]$p.HomeRestore
        $Script:LoadedGuiSettings['HomeShader']  = [bool]$p.HomeShader
        $Script:LoadedGuiSettings['HomeGaming']  = [bool]$p.HomeGaming
        $Script:LoadedGuiSettings['HomeWU']      = [bool]$p.HomeWU
        $Script:LoadedGuiSettings['HomeWinget']  = [bool]$p.HomeWinget
    }
}

function Apply-ScheduledCareFlags {
    # Used by -Mode Scheduled: honor saved Home checkboxes / last preset.
    $s = Load-GuiSettings
    Reset-MaintenanceFlags
    $Script:DoCleanup = $true
    $Script:DoRestorePoint = [bool]$s.HomeRestore
    $Script:DoShaderCleanup = [bool]$s.HomeShader
    $Script:DoGamingOptimize = [bool]$s.HomeGaming
    $Script:DoWinUpdate = [bool]$s.HomeWU
    $Script:DoWinget = [bool]$s.HomeWinget
    $Script:DoAmd = $false
    $Script:DoRepair = $false
    $Script:DoWuCacheWipe = $false
    if ($s.TempOlderDays -ne $null) {
        try { $Script:TempOlderThanDays = [int]$s.TempOlderDays } catch { }
    }
}

function Get-WeeklyCareTask {
    try {
        return Get-ScheduledTask -TaskName $Script:WeeklyCareTaskName -EA SilentlyContinue
    } catch {
        return $null
    }
}

function Test-WeeklyCareScheduled {
    $t = Get-WeeklyCareTask
    return [bool]($t -and $t.State -ne 'Disabled')
}

function Get-WeeklyCareScheduleStatusText {
    $t = Get-WeeklyCareTask
    if (-not $t) { return "Weekly schedule: off" }
    if ($t.State -eq 'Disabled') { return "Weekly schedule: disabled" }
    try {
        $info = Get-ScheduledTaskInfo -TaskName $Script:WeeklyCareTaskName -EA Stop
        $next = $info.NextRunTime
        if ($next -and $next -gt [datetime]::MinValue) {
            return ("Weekly schedule: Sun 6 PM  (next {0})" -f $next.ToString('g'))
        }
    } catch { }
    return "Weekly schedule: on (Sundays 6 PM)"
}

function Enable-WeeklyCareSchedule {
    param(
        [string]$ScriptPath
    )
    if (-not $ScriptPath) { $ScriptPath = $PSCommandPath }
    if (-not $ScriptPath -or -not (Test-Path -LiteralPath $ScriptPath)) {
        $ScriptPath = Join-Path $Script:AppRoot 'PC-Maintenance.ps1'
    }
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Cannot locate PC-Maintenance.ps1 to schedule."
    }

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -Mode Scheduled"
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $arg
    # Sundays at 18:00 local time
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 6:00PM
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 4)
    $principal = New-ScheduledTaskPrincipal `
        -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -RunLevel Highest `
        -LogonType Interactive

    Register-ScheduledTask `
        -TaskName $Script:WeeklyCareTaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Force | Out-Null

    if ($Script:LoadedGuiSettings) {
        $Script:LoadedGuiSettings['ScheduleWeekly'] = $true
    }
    return $true
}

function Disable-WeeklyCareSchedule {
    $t = Get-WeeklyCareTask
    if ($t) {
        Unregister-ScheduledTask -TaskName $Script:WeeklyCareTaskName -Confirm:$false -EA Stop
    }
    if ($Script:LoadedGuiSettings) {
        $Script:LoadedGuiSettings['ScheduleWeekly'] = $false
    }
    return $true
}

function Update-GuiCareScheduleStatus {
    if (-not $Script:GuiControls) { return }
    $lbl = $Script:GuiControls.LblScheduleStatus
    $chk = $Script:GuiControls.ChkScheduleWeekly
    if ($lbl) {
        try { $lbl.Text = Get-WeeklyCareScheduleStatusText } catch { $lbl.Text = "Weekly schedule: ?" }
    }
    if ($chk) {
        try {
            $on = Test-WeeklyCareScheduled
            if ($chk.Checked -ne $on) { $chk.Checked = $on }
        } catch { }
    }
}
