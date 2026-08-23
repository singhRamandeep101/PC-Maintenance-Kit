#Requires -Version 5.1
$Script:AppVersion = "5.1.4"
$Script:GitHubRepo = "singhRamandeep101/PC-Maintenance-Kit"

function Get-AppDataDirectory {
    $dir = Join-Path $env:LOCALAPPDATA "PC-Maintenance-Kit"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-GuiSettingsPath {
    $path = Join-Path (Get-AppDataDirectory) "gui-settings.json"
    if (Test-PathSafe $path) { return $path }

    $legacy = [System.Collections.Generic.List[string]]::new()
    [void]$legacy.Add((Join-Path $env:USERPROFILE "Desktop\PC-Maintenance-Logs\gui-settings.json"))
    if ($Script:AppRoot) {
        [void]$legacy.Add((Join-Path $Script:AppRoot "PC-Maintenance-Logs\gui-settings.json"))
    }
    foreach ($old in $legacy) {
        if (Test-PathSafe $old) {
            try { Copy-Item -LiteralPath $old -Destination $path -Force } catch { }
            break
        }
    }
    return $path
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
        $req.Timeout = 12000
        $resp = $req.GetResponse()
        try {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $json = $reader.ReadToEnd() | ConvertFrom-Json
            $zipAsset = @($json.assets) |
                Where-Object { $_.name -and ($_.name -match '\.zip$') -and $_.browser_download_url } |
                Select-Object -First 1
            return [pscustomobject]@{
                Tag     = [string]$json.tag_name
                Name    = [string]$json.name
                Url     = [string]$json.html_url
                Latest  = ([string]$json.tag_name).TrimStart('v', 'V')
                ZipUrl  = if ($zipAsset) { [string]$zipAsset.browser_download_url } else { $null }
                ZipName = if ($zipAsset) { [string]$zipAsset.name } else { $null }
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

function Invoke-AppSelfUpdate {
    param($Release)
    if (-not $Release) { throw "No release info" }
    if (-not $Release.ZipUrl) {
        throw "This GitHub release has no ZIP attached. Re-publish the release with the build ZIP."
    }
    if (-not $Script:AppRoot -or -not (Test-Path -LiteralPath $Script:AppRoot)) {
        throw "App folder not found."
    }

    $work = Join-Path $env:TEMP ("PCMK-update-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    $extract = Join-Path $work "extract"
    $zipName = if ($Release.ZipName) { $Release.ZipName } else { "update.zip" }
    $zipPath = Join-Path $work $zipName
    New-Item -ItemType Directory -Path $extract -Force | Out-Null

    Write-Info ("Downloading {0}..." -f $Release.Tag)
    Set-UiStatusText ("Downloading {0}..." -f $Release.Tag)
    Pump-Ui

    $download = Invoke-WithUiWait -Activity ("Downloading {0}" -f $Release.Tag) -TimeoutSec 300 -ArgumentList @($Release.ZipUrl, $zipPath) -ScriptBlock {
        param([string]$Url, [string]$OutFile)
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "PC-Maintenance-Kit")
            $wc.DownloadFile($Url, $OutFile)
            if (-not (Test-Path -LiteralPath $OutFile) -or ((Get-Item -LiteralPath $OutFile).Length -lt 1000)) {
                "ERR:Download too small or missing"
            } else {
                "OK"
            }
        } catch {
            "ERR:" + $_.Exception.Message
        }
    }
    $dlText = Get-AsyncResultText $download
    if ($dlText -ne "OK") {
        $msg = if ($dlText -like "ERR:*") { $dlText.Substring(4) } elseif ($null -eq $dlText) { "download timed out" } else { $dlText }
        throw "Download failed: $msg"
    }
    Write-Ok ("Downloaded {0}" -f $zipName)

    Write-Info "Extracting update..."
    Set-UiStatusText "Extracting update..."
    Pump-Ui
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force

    $payloadPs1 = Get-ChildItem -LiteralPath $extract -Recurse -Filter "PC-Maintenance.ps1" -File -EA SilentlyContinue |
        Select-Object -First 1
    if (-not $payloadPs1) {
        throw "Update ZIP is missing PC-Maintenance.ps1"
    }
    $payloadRoot = Split-Path -Parent $payloadPs1.FullName

    $applyPs1 = Join-Path $work "Apply-Update.ps1"
    $startBat = Join-Path $Script:AppRoot "Start.bat"
    $applyBody = @"
#Requires -Version 5.1
`$ErrorActionPreference = 'Continue'
`$target = @'
$($Script:AppRoot)
'@
`$source = @'
$payloadRoot
'@
`$parentPid = $PID
`$startBat = @'
$startBat
'@
`$work = @'
$work
'@

try {
    `$deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt `$deadline) {
        try {
            `$p = Get-Process -Id `$parentPid -EA Stop
            if (-not `$p -or `$p.HasExited) { break }
        } catch { break }
        Start-Sleep -Milliseconds 400
    }
    Start-Sleep -Seconds 1

    if (-not (Test-Path -LiteralPath `$source)) { throw "Update source missing" }
    if (-not (Test-Path -LiteralPath `$target)) { throw "App folder missing" }

    # robocopy avoids Copy-Item nesting bug (lib -> lib\lib when destination exists)
    `$rc = Join-Path `$env:SystemRoot 'System32\robocopy.exe'
    & `$rc `$source `$target /E /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    `$code = `$LASTEXITCODE
    if (`$code -ge 8) { throw "robocopy failed with code `$code" }

    if (Test-Path -LiteralPath `$startBat) {
        Start-Process -FilePath `$startBat -WorkingDirectory `$target
    } else {
        `$ps1 = Join-Path `$target 'PC-Maintenance.ps1'
        `$ps = Join-Path `$env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath `$ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',`$ps1,'-Mode','Gui') -WorkingDirectory `$target
    }
} catch {
    `$errDir = Join-Path `$env:TEMP 'PC-Maintenance-Kit'
    if (-not (Test-Path `$errDir)) { New-Item -ItemType Directory -Path `$errDir -Force | Out-Null }
    `$_ | Out-File (Join-Path `$errDir 'update-error.log') -Encoding utf8
} finally {
    Start-Sleep -Seconds 2
    try { Remove-Item -LiteralPath `$work -Recurse -Force -EA SilentlyContinue } catch { }
}
"@
    Set-Content -LiteralPath $applyPs1 -Value $applyBody -Encoding UTF8

    Write-Info "Installing update and restarting..."
    Set-UiStatusText "Installing update and restarting..."
    Pump-Ui

    $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    Start-Process -FilePath $psExe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $applyPs1
    ) | Out-Null

    # Close cleanly after UI handlers unwind (exit/Close here causes WinForms "System error")
    $Script:ExitAfterUpdate = $true
    Write-Ok "Update ready - restarting..."
}

function Show-UpdateAvailableDialog {
    param($Release)
    if (-not $Release) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
        $hasZip = [bool]$Release.ZipUrl
        $msg = if ($hasZip) {
            "A newer release is available.`n`nThis PC: v{0}`nLatest: {1}`n`nDownload and install now?`nThe app will restart automatically." -f $Script:AppVersion, $Release.Tag
        } else {
            "A newer release is available.`n`nThis PC: v{0}`nLatest: {1}`n`nNo ZIP is attached to this release, so one-click update is unavailable.`nOpen GitHub releases page?" -f $Script:AppVersion, $Release.Tag
        }
        $r = [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "PC Maintenance Kit - Update",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        if ($hasZip) {
            try {
                Invoke-AppSelfUpdate -Release $Release
            } catch {
                $Script:ExitAfterUpdate = $false
                Write-Fail $_.Exception.Message
                $fallback = [System.Windows.Forms.MessageBox]::Show(
                    ("Automatic update failed:`n{0}`n`nOpen GitHub releases page instead?" -f $_.Exception.Message),
                    "PC Maintenance Kit - Update",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                if ($fallback -eq [System.Windows.Forms.DialogResult]::Yes -and $Release.Url) {
                    Start-Process $Release.Url
                }
            }
        } elseif ($Release.Url) {
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
