#Requires -Version 5.1
$Script:AppVersion = "5.1.1"
$Script:GitHubRepo = "singhRamandeep101/PC-Maintenance-Kit"

function Get-LogsDirectory {
    $dir = Join-Path $env:USERPROFILE "Desktop\PC-Maintenance-Logs"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-GuiSettingsPath {
    Join-Path (Get-LogsDirectory) "gui-settings.json"
}

function Get-DefaultGuiSettings {
    return [ordered]@{
        HomeRestore     = $true
        HomeShader      = $true
        HomeGaming      = $true
        HomeWU          = $false
        HomeWinget      = $false
        TempOlderDays   = 2
        CleanShader     = $true
        CleanSteam      = $false
        CleanEpic       = $false
        CleanRiot       = $false
        UpdRestore      = $true
        UpdWU           = $true
        UpdWinget       = $true
        RepRestore      = $true
        CheckUpdatesOnStart = $true
    }
}

function Save-GuiSettings {
    param($Controls)
    if (-not $Controls) { return }
    try {
        $checkUpdates = $true
        if ($Script:LoadedGuiSettings -and $null -ne $Script:LoadedGuiSettings.CheckUpdatesOnStart) {
            $checkUpdates = [bool]$Script:LoadedGuiSettings.CheckUpdatesOnStart
        }
        $obj = [ordered]@{
            HomeRestore     = [bool]$Controls.ChkHomeRestore.Checked
            HomeShader      = [bool]$Controls.ChkHomeShader.Checked
            HomeGaming      = [bool]$Controls.ChkHomeGaming.Checked
            HomeWU          = [bool]$Controls.ChkHomeWU.Checked
            HomeWinget      = [bool]$Controls.ChkHomeWinget.Checked
            TempOlderDays   = [int]$Controls.DaysNum.Value
            CleanShader     = [bool]$Controls.ChkCleanShader.Checked
            CleanSteam      = [bool]$Controls.ChkSteam.Checked
            CleanEpic       = [bool]$Controls.ChkEpic.Checked
            CleanRiot       = [bool]$Controls.ChkRiot.Checked
            UpdRestore      = [bool]$Controls.ChkUpdRestore.Checked
            UpdWU           = [bool]$Controls.ChkUpdWU.Checked
            UpdWinget       = [bool]$Controls.ChkUpdWinget.Checked
            RepRestore      = [bool]$Controls.ChkRepRestore.Checked
            CheckUpdatesOnStart = $checkUpdates
        }
        $Script:LoadedGuiSettings = $obj
        $json = ($obj | ConvertTo-Json -Depth 5)
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Get-GuiSettingsPath), $json, $utf8)
    } catch { }
}

function Load-GuiSettings {
    $path = Get-GuiSettingsPath
    $defaults = Get-DefaultGuiSettings
    if (-not (Test-PathSafe $path)) { return $defaults }
    try {
        $raw = [System.IO.File]::ReadAllText($path)
        $j = $raw | ConvertFrom-Json
        foreach ($k in $defaults.Keys) {
            if ($null -ne $j.PSObject.Properties[$k]) {
                $defaults[$k] = $j.$k
            }
        }
    } catch { }
    return $defaults
}

function Apply-GuiSettings {
    param($Controls, $Settings)
    if (-not $Controls -or -not $Settings) { return }
    try {
        $Controls.ChkHomeRestore.Checked = [bool]$Settings.HomeRestore
        $Controls.ChkHomeShader.Checked  = [bool]$Settings.HomeShader
        $Controls.ChkHomeGaming.Checked  = [bool]$Settings.HomeGaming
        $Controls.ChkHomeWU.Checked      = [bool]$Settings.HomeWU
        $Controls.ChkHomeWinget.Checked  = [bool]$Settings.HomeWinget
        $days = [int]$Settings.TempOlderDays
        if ($days -lt 0) { $days = 0 }
        if ($days -gt 30) { $days = 30 }
        $Controls.DaysNum.Value = $days
        $Controls.ChkCleanShader.Checked = [bool]$Settings.CleanShader
        $Controls.ChkSteam.Checked       = [bool]$Settings.CleanSteam
        $Controls.ChkEpic.Checked        = [bool]$Settings.CleanEpic
        $Controls.ChkRiot.Checked        = [bool]$Settings.CleanRiot
        $Controls.ChkUpdRestore.Checked  = [bool]$Settings.UpdRestore
        $Controls.ChkUpdWU.Checked       = [bool]$Settings.UpdWU
        $Controls.ChkUpdWinget.Checked   = [bool]$Settings.UpdWinget
        $Controls.ChkRepRestore.Checked  = [bool]$Settings.RepRestore
    } catch { }
}

function Get-FolderSizeBytes {
    param([string]$Path, [int]$OlderThanDays = 0)
    if (-not (Test-PathSafe $Path)) { return 0L }
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $sum = 0L
    try {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -File -EA SilentlyContinue |
            Where-Object { $OlderThanDays -le 0 -or $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                $sum += $_.Length
                if (($sum % 200) -eq 0) { Pump-UiThrottled }
            }
    } catch { }
    return $sum
}

function Get-EpicCachePaths {
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache_4430",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Data",
        "$env:PROGRAMDATA\Epic\EpicGamesLauncher\Data\EMS"
    )) {
        if (Test-PathSafe $p) { [void]$list.Add($p) }
    }
    # Common Epic download/install staging folders when drive exists
    foreach ($root in @('C:\Program Files\Epic Games', 'D:\Epic Games', 'E:\Epic Games')) {
        if ($root -match '^[A-Za-z]:' -and -not (Test-PathSafe ($root.Substring(0, 1) + ':\'))) { continue }
        $dl = Join-PathSafe $root '.egstore'
        if ($dl -and (Test-PathSafe $dl)) { [void]$list.Add($dl) }
    }
    return @($list)
}

function Get-CleanupPreview {
    param(
        [int]$TempOlderThanDays = 2,
        [bool]$Shaders = $true,
        [bool]$Steam = $false,
        [bool]$Epic = $false,
        [bool]$Riot = $false
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    $total = 0L

    $tempPaths = @(
        $env:TEMP,
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows\Temp",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"
    )
    foreach ($p in $tempPaths) {
        if (-not (Test-PathSafe $p)) { continue }
        $bytes = Get-FolderSizeBytes $p $TempOlderThanDays
        if ($bytes -le 0 -and -not (Test-PathSafe $p)) { continue }
        $total += $bytes
        [void]$rows.Add([pscustomobject]@{
            Label = "Temp"
            Path  = $p
            Bytes = $bytes
            Size  = if ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes / 1MB) } else { "{0:N0} KB" -f ($bytes / 1KB) }
        })
    }

    if ($Shaders) {
        foreach ($p in @(
            "$env:LOCALAPPDATA\D3DSCache",
            "$env:LOCALAPPDATA\AMD\DxCache",
            "$env:LOCALAPPDATA\AMD\Dx9Cache",
            "$env:LOCALAPPDATA\AMD\DxcCache",
            "$env:LOCALAPPDATA\NVIDIA\DXCache",
            "$env:LOCALAPPDATA\NVIDIA\GLCache",
            "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"
        )) {
            if (-not (Test-PathSafe $p)) { continue }
            $bytes = Get-FolderSizeBytes $p 0
            $total += $bytes
            [void]$rows.Add([pscustomobject]@{
                Label = "Shader"
                Path  = $p
                Bytes = $bytes
                Size  = if ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes / 1MB) } else { "{0:N0} KB" -f ($bytes / 1KB) }
            })
        }
    }

    if ($Steam) {
        foreach ($p in @(Get-SteamDownloadingPaths)) {
            $bytes = Get-FolderSizeBytes $p 0
            $total += $bytes
            [void]$rows.Add([pscustomobject]@{
                Label = "Steam"
                Path  = $p
                Bytes = $bytes
                Size  = if ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes / 1MB) } else { "{0:N0} KB" -f ($bytes / 1KB) }
            })
        }
    }
    if ($Epic) {
        foreach ($p in @(Get-EpicCachePaths)) {
            $bytes = Get-FolderSizeBytes $p 0
            $total += $bytes
            [void]$rows.Add([pscustomobject]@{
                Label = "Epic"
                Path  = $p
                Bytes = $bytes
                Size  = if ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes / 1MB) } else { "{0:N0} KB" -f ($bytes / 1KB) }
            })
        }
    }
    if ($Riot) {
        foreach ($p in @(
            "$env:LOCALAPPDATA\Riot Games\Riot Client\CefCache",
            "$env:LOCALAPPDATA\Riot Games\Riot Client\Logs"
        )) {
            if (-not (Test-PathSafe $p)) { continue }
            $bytes = Get-FolderSizeBytes $p 0
            $total += $bytes
            [void]$rows.Add([pscustomobject]@{
                Label = "Riot"
                Path  = $p
                Bytes = $bytes
                Size  = if ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes / 1MB) } else { "{0:N0} KB" -f ($bytes / 1KB) }
            })
        }
    }

    return [pscustomobject]@{
        Rows       = @($rows)
        TotalBytes = $total
        TotalText  = if ($total -ge 1GB) { "{0:N2} GB" -f ($total / 1GB) } else { "{0:N1} MB" -f ($total / 1MB) }
    }
}

function Show-CleanupPreviewDialog {
    param($Preview)
    Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
    Add-Type -AssemblyName System.Drawing -EA SilentlyContinue

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Cleanup preview"
    $form.Size = New-Object System.Drawing.Size(720, 480)
    $form.StartPosition = "CenterParent"
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = ("Approx reclaimable: {0}`nNothing has been deleted yet." -f $Preview.TotalText)
    $lbl.Location = New-Object System.Drawing.Point(16, 12)
    $lbl.Size = New-Object System.Drawing.Size(670, 40)
    $form.Controls.Add($lbl)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(16, 56)
    $grid.Size = New-Object System.Drawing.Size(670, 320)
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AutoSizeColumnsMode = "Fill"
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = "FullRowSelect"
    $null = $grid.Columns.Add("Label", "Type")
    $null = $grid.Columns.Add("Size", "Size")
    $null = $grid.Columns.Add("Path", "Path")
    foreach ($r in @($Preview.Rows)) {
        [void]$grid.Rows.Add($r.Label, $r.Size, $r.Path)
    }
    $form.Controls.Add($grid)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Run cleanup"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $btnOk.Location = New-Object System.Drawing.Point(470, 390)
    $btnOk.Size = New-Object System.Drawing.Size(120, 32)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::No
    $btnCancel.Location = New-Object System.Drawing.Point(600, 390)
    $btnCancel.Size = New-Object System.Drawing.Size(86, 32)

    $form.Controls.AddRange(@($btnOk, $btnCancel))
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel
    return $form.ShowDialog()
}

function Get-RunSummaryObject {
    $ok = @($Script:Report | Where-Object { $_ -like '[OK]*' }).Count
    $warn = @($Script:Report | Where-Object { $_ -like '[!]*' }).Count
    $fail = @($Script:Report | Where-Object { $_ -like '[X]*' }).Count
    $end = Get-CFreeGB
    if (-not $Script:StartFree) { $Script:StartFree = $end }
    $gained = [math]::Round($end - $Script:StartFree, 1)
    return [pscustomobject]@{
        Elapsed       = Get-Elapsed
        FreeBefore    = $Script:StartFree
        FreeAfter     = $end
        SpaceChange   = $gained
        OkCount       = $ok
        WarnCount     = $warn
        FailCount     = $fail
        RebootPending = [bool](Test-RebootPending)
        LogFile       = $Script:LogFile
        ReportLines   = @($Script:Report)
    }
}

function Show-RunSummaryDialog {
    param(
        [string]$Title = "Run summary",
        $Summary = $null
    )
    if (-not $Summary) { $Summary = Get-RunSummaryObject }
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
        $reboot = if ($Summary.RebootPending) { "Yes - restart recommended" } else { "No" }
        $body = @(
            "Time: $($Summary.Elapsed)"
            "C: free: $($Summary.FreeBefore) GB -> $($Summary.FreeAfter) GB ($($Summary.SpaceChange) GB)"
            "Results: $($Summary.OkCount) OK | $($Summary.WarnCount) warn | $($Summary.FailCount) fail"
            "Restart pending: $reboot"
            "Log: $($Summary.LogFile)"
        ) -join "`n"
        [System.Windows.Forms.MessageBox]::Show(
            $body,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $(if ($Summary.FailCount -gt 0) {
                [System.Windows.Forms.MessageBoxIcon]::Warning
            } else {
                [System.Windows.Forms.MessageBoxIcon]::Information
            })
        ) | Out-Null
    } catch { }
}

function Get-GitHubLatestRelease {
    param([string]$Repo = $Script:GitHubRepo)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $url = "https://api.github.com/repos/$Repo/releases/latest"
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.UserAgent = "PC-Maintenance-Kit"
        $req.Accept = "application/vnd.github+json"
        $req.Timeout = 8000
        $resp = $req.GetResponse()
        try {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $json = $reader.ReadToEnd() | ConvertFrom-Json
            return [pscustomobject]@{
                Tag    = [string]$json.tag_name
                Name   = [string]$json.name
                Url    = [string]$json.html_url
                Latest = ([string]$json.tag_name).TrimStart('v', 'V')
            }
        } finally {
            $resp.Close()
        }
    } catch {
        return $null
    }
}

function Compare-AppVersion {
    param([string]$Current, [string]$Other)
    try {
        $c = [version]($Current -replace '[^\d\.]', '')
        $o = [version]($Other -replace '[^\d\.]', '')
        return $c.CompareTo($o)
    } catch {
        return 0
    }
}

function Test-AppUpdateAvailable {
    param([switch]$Silent)
    $rel = Get-GitHubLatestRelease
    if (-not $rel -or -not $rel.Latest) {
        if (-not $Silent) {
            Write-Info "Update check: no GitHub release found (or offline)"
        }
        return [pscustomobject]@{
            Status  = 'Unavailable'
            Release = $null
        }
    }
    $cmp = Compare-AppVersion -Current $Script:AppVersion -Other $rel.Latest
    if ($cmp -lt 0) {
        return [pscustomobject]@{
            Status  = 'UpdateAvailable'
            Release = $rel
        }
    }
    if (-not $Silent) {
        Write-Info ("Up to date (v{0}, GitHub {1})" -f $Script:AppVersion, $rel.Tag)
    }
    return [pscustomobject]@{
        Status  = 'UpToDate'
        Release = $rel
    }
}

function Show-UpdateAvailableDialog {
    param($Release)
    if (-not $Release) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
        $r = [System.Windows.Forms.MessageBox]::Show(
            ("A newer release is available.`n`nThis PC: v{0}`nLatest: {1}`n`nOpen GitHub releases page?" -f $Script:AppVersion, $Release.Tag),
            "PC Maintenance Kit - Update",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes -and $Release.Url) {
            Start-Process $Release.Url
        }
    } catch { }
}

function Start-ElevatedCli {
    $scriptPath = Join-Path $Script:AppRoot "PC-Maintenance.ps1"
    if (-not (Test-PathSafe $scriptPath)) { throw "PC-Maintenance.ps1 not found" }
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$scriptPath`" -Mode Cli"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps
    $psi.Arguments = $args
    $psi.WorkingDirectory = $Script:AppRoot
    $psi.UseShellExecute = $true
    # Already elevated GUI -> child inherits admin; Verb runas still works if needed
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = [Security.Principal.WindowsPrincipal]::new($id)
        if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $psi.Verb = "runas"
        }
    } catch { }
    [System.Diagnostics.Process]::Start($psi) | Out-Null
}
