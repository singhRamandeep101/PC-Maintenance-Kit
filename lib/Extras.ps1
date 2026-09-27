#Requires -Version 5.1
function Get-KitVersion {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($Script:AppRoot) { [void]$candidates.Add((Join-Path $Script:AppRoot 'VERSION')) }
    if ($PSScriptRoot) {
        [void]$candidates.Add((Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'))
        [void]$candidates.Add((Join-Path $PSScriptRoot 'VERSION'))
    }
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path -EA SilentlyContinue)) {
            try {
                $raw = (Get-Content -LiteralPath $path -Raw -EA Stop).Trim()
                if ($raw -match '^\d+(\.\d+){1,3}$') { return $raw }
            } catch { }
        }
    }
    # No VERSION file means a broken/partial install - report it rather than
    # inventing a number that drifts out of sync with the real release.
    return '0.0.0'
}

$Script:AppVersion = Get-KitVersion
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
        CleanWuCache    = $false
        UpdRestore      = $true
        UpdWU           = $true
        UpdWinget       = $true
        RepRestore      = $true
        CheckUpdatesOnStart = $true
        CarePreset      = 'Gamer'
        ScheduleWeekly  = $false
    }
}

function Save-GuiSettings {
    param($Controls)
    if (-not $Controls) { return }
    try {
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
            CleanWuCache    = [bool]$Controls.ChkWuCache.Checked
            UpdRestore      = [bool]$Controls.ChkUpdRestore.Checked
            UpdWU           = [bool]$Controls.ChkUpdWU.Checked
            UpdWinget       = [bool]$Controls.ChkUpdWinget.Checked
            RepRestore      = [bool]$Controls.ChkRepRestore.Checked
        }
        # Carry forward every key that has no control behind it, including keys
        # written by a newer build, so a save never silently drops settings.
        if ($Script:LoadedGuiSettings) {
            foreach ($k in @($Script:LoadedGuiSettings.Keys)) {
                if (-not $obj.Contains($k)) { $obj[$k] = $Script:LoadedGuiSettings[$k] }
            }
        }
        if (-not $Script:DefaultGuiSettingsCache) {
            $Script:DefaultGuiSettingsCache = Get-DefaultGuiSettings
        }
        foreach ($k in $Script:DefaultGuiSettingsCache.Keys) {
            if (-not $obj.Contains($k)) { $obj[$k] = $Script:DefaultGuiSettingsCache[$k] }
        }
        $json = ($obj | ConvertTo-Json -Depth 5)
        if ($Script:LastSavedGuiSettingsJson -and $Script:LastSavedGuiSettingsJson -eq $json) {
            $Script:LoadedGuiSettings = $obj
            return
        }
        $Script:LoadedGuiSettings = $obj
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Get-GuiSettingsPath), $json, $utf8)
        $Script:LastSavedGuiSettingsJson = $json
    } catch {
        Write-Warn ("Could not save GUI settings: {0}" -f $_.Exception.Message)
    }
}

function Load-GuiSettings {
    $path = Get-GuiSettingsPath
    $defaults = Get-DefaultGuiSettings
    if (-not (Test-PathSafe $path)) { return $defaults }
    try {
        $raw = [System.IO.File]::ReadAllText($path)
        $j = $raw | ConvertFrom-Json
        # Overlay everything on disk, including keys this build does not know,
        # so downgrading then upgrading does not lose a newer build's settings.
        foreach ($prop in $j.PSObject.Properties) {
            $defaults[$prop.Name] = $prop.Value
        }
    } catch { }
    return $defaults
}

function Get-GuiSettingControlMap {
    return [ordered]@{
        ChkHomeRestore  = 'HomeRestore'
        ChkHomeShader   = 'HomeShader'
        ChkHomeGaming   = 'HomeGaming'
        ChkHomeWU       = 'HomeWU'
        ChkHomeWinget   = 'HomeWinget'
        ChkCleanShader  = 'CleanShader'
        ChkSteam        = 'CleanSteam'
        ChkEpic         = 'CleanEpic'
        ChkRiot         = 'CleanRiot'
        ChkWuCache      = 'CleanWuCache'
        ChkUpdRestore   = 'UpdRestore'
        ChkUpdWU        = 'UpdWU'
        ChkUpdWinget    = 'UpdWinget'
        ChkRepRestore   = 'RepRestore'
    }
}

function Apply-GuiSettings {
    param($Controls, $Settings)
    if (-not $Controls -or -not $Settings) { return }

    # Each setting is applied independently - one bad value used to abort the
    # whole restore silently and leave the rest of the UI on its defaults.
    $failed = [System.Collections.Generic.List[string]]::new()
    $map = Get-GuiSettingControlMap
    foreach ($ctrlName in $map.Keys) {
        $key = $map[$ctrlName]
        $ctrl = $Controls.$ctrlName
        if (-not $ctrl) { continue }
        try { $ctrl.Checked = [bool]$Settings.$key } catch { [void]$failed.Add($key) }
    }

    try {
        $days = [int]$Settings.TempOlderDays
        if ($days -lt 0) { $days = 0 }
        if ($days -gt 30) { $days = 30 }
        if ($Controls.DaysNum) { $Controls.DaysNum.Value = $days }
    } catch {
        [void]$failed.Add('TempOlderDays')
    }

    if ($failed.Count -gt 0) {
        Write-Warn ("Could not restore {0} setting(s): {1}" -f $failed.Count, ($failed -join ', '))
    }
}

function Get-FolderSizeBytes {
    param([string]$Path, [int]$OlderThanDays = 0)
    if (-not (Test-PathSafe $Path)) { return 0L }
    if (-not (Get-Command Measure-ContainedTreeBytes -EA SilentlyContinue)) { return 0L }
    return [long](Measure-ContainedTreeBytes -Root $Path -OlderThanDays $OlderThanDays)
}

function Get-EpicCachePaths {
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache_4430",
        "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Logs",
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
        [bool]$Riot = $false,
        [bool]$WuCache = $false
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    $total = 0L

    $tempRaw = @(
        $env:TEMP,
        "$env:LOCALAPPDATA\Temp",
        $(if (Get-Command Get-WindowsTempPath -EA SilentlyContinue) { Get-WindowsTempPath } else { 'C:\Windows\Temp' }),
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"
    )
    $tempPaths = if (Get-Command Select-UniqueCleanupPaths -EA SilentlyContinue) {
        @(Select-UniqueCleanupPaths -Paths $tempRaw)
    } else { $tempRaw }
    foreach ($p in $tempPaths) {
        if (-not (Test-PathSafe $p)) { continue }
        Write-Info ("Measuring {0}" -f $p)
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

    $browserMap = Get-BrowserCachePaths
    foreach ($browser in $browserMap.Keys) {
        foreach ($p in $browserMap[$browser]) {
            Write-Info ("Measuring {0}" -f $p)
            $bytes = Get-FolderSizeBytes $p 0
            $total += $bytes
            [void]$rows.Add([pscustomobject]@{
                Label = "Browser/$browser"
                Path  = $p
                Bytes = $bytes
                Size  = if ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes / 1MB) } else { "{0:N0} KB" -f ($bytes / 1KB) }
            })
        }
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

    if ($WuCache) {
        $wuPath = if (Get-Command Get-WindowsUpdateDownloadPath -EA SilentlyContinue) { Get-WindowsUpdateDownloadPath } else { 'C:\Windows\SoftwareDistribution\Download' }
        if (Test-PathSafe $wuPath) {
            $bytes = Get-FolderSizeBytes $wuPath 0
            $total += $bytes
            [void]$rows.Add([pscustomobject]@{
                Label = "WU Download Cache"
                Path  = $wuPath
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
    return Invoke-WithUiModal { $form.ShowDialog() }
}

function Get-RunSummaryObject {
    $ok = @($Script:Report | Where-Object { $_ -like '[OK]*' }).Count
    $warn = @($Script:Report | Where-Object { $_ -like '[!]*' }).Count
    $fail = @($Script:Report | Where-Object { $_ -like '[X]*' }).Count
    $end = Get-CFreeGB -Refresh
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
        RebootPending = [bool](Test-RebootPending -Refresh)
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
        [void](Show-UiMessageBox `
            -Text $body `
            -Caption $Title `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
            -Icon $(if ($Summary.FailCount -gt 0) {
                [System.Windows.Forms.MessageBoxIcon]::Warning
            } else {
                [System.Windows.Forms.MessageBoxIcon]::Information
            }))
    } catch { }
}

function Get-ExpectedSha256Text {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $line = (($Text -split "`r?`n") | Where-Object { $_ -and ($_ -notmatch '^\s*#') } | Select-Object -First 1)
    if ($line -match '([A-Fa-f0-9]{64})') { return $Matches[1].ToLowerInvariant() }
    return $null
}

function Select-KitReleaseZip {
    param($Assets)
    $zips = @($Assets | Where-Object {
        $_.name -and ($_.name -match '\.zip$') -and ($_.name -notmatch '\.sha256') -and $_.browser_download_url
    })
    $named = @($zips | Where-Object { $_.name -like 'PC-Maintenance-Kit-v*.zip' })
    if ($named.Count -gt 0) { return $named[0] }
    return ($zips | Select-Object -First 1)
}

function Select-KitReleaseChecksum {
    param($Assets, [string]$ZipName)
    $sums = @($Assets | Where-Object { $_.name -and ($_.name -match '\.sha256$') -and $_.browser_download_url })
    if ($ZipName) {
        $match = @($sums | Where-Object { $_.name -eq ($ZipName + '.sha256') } | Select-Object -First 1)
        if ($match) { return $match[0] }
    }
    return ($sums | Select-Object -First 1)
}

function Resolve-KitPayloadRoot {
    param([string]$Extract)
    if ([string]::IsNullOrWhiteSpace($Extract) -or -not (Test-Path -LiteralPath $Extract)) { return $null }
    foreach ($cand in @(Get-ChildItem -LiteralPath $Extract -Recurse -Filter 'PC-Maintenance.ps1' -File -EA SilentlyContinue)) {
        $root = Split-Path -Parent $cand.FullName
        if (Test-Path -LiteralPath (Join-Path $root 'lib\Core.ps1')) { return $root }
    }
    return $null
}

function Assert-KitScriptsAuthenticode {
    # Unsigned scripts are allowed (signing is optional). A signature that is
    # present must be Valid — HashMismatch, NotTrusted, and UnknownError are rejected.
    param([string]$Folder)
    Get-ChildItem -LiteralPath $Folder -Recurse -Filter *.ps1 -File -EA SilentlyContinue | ForEach-Object {
        $sig = Get-AuthenticodeSignature -FilePath $_.FullName
        $status = [string]$sig.Status
        if ($status -eq 'NotSigned') { return }
        if ($status -ne 'Valid') {
            throw ("Rejected {0}: Authenticode status is {1}" -f $_.Name, $status)
        }
    }
}

function Test-KitPayloadHealthy {
    param([string]$Root)
    try {
        $entry = Join-Path $Root 'PC-Maintenance.ps1'
        $core = Join-Path $Root 'lib\Core.ps1'
        if (-not (Test-Path -LiteralPath $entry)) { return $false }
        if (-not (Test-Path -LiteralPath $core)) { return $false }
        foreach ($f in @($entry, $core)) {
            $errs = $null
            $toks = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
            if ($errs -and $errs.Count -gt 0) { return $false }
        }
        return $true
    } catch {
        return $false
    }
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
            $zipAsset = Select-KitReleaseZip -Assets @($json.assets)
            $sumAsset = Select-KitReleaseChecksum -Assets @($json.assets) -ZipName $(if ($zipAsset) { [string]$zipAsset.name } else { '' })
            $digest = $null
            if ($zipAsset -and $zipAsset.digest) {
                $digest = Get-ExpectedSha256Text ([string]$zipAsset.digest)
            }
            return [pscustomobject]@{
                Tag            = [string]$json.tag_name
                Name           = [string]$json.name
                Url            = [string]$json.html_url
                Latest         = ([string]$json.tag_name).TrimStart('v', 'V')
                ZipUrl         = if ($zipAsset) { [string]$zipAsset.browser_download_url } else { $null }
                ZipName        = if ($zipAsset) { [string]$zipAsset.name } else { $null }
                Sha256Url      = if ($sumAsset) { [string]$sumAsset.browser_download_url } else { $null }
                DigestSha256   = $digest
                ExpectedSha256 = $digest
            }
        } finally {
            $resp.Close()
        }
    } catch {
        return $null
    }
}

function ConvertTo-ComparableVersion {
    # Keep only the leading numeric core: "v5.3.0-rc1" -> 5.3.0, not 5.3.0.1
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match([string]$Text, '(\d+(?:\.\d+){0,3})')
    if (-not $m.Success) { return $null }
    $core = $m.Groups[1].Value.Trim('.')
    if (-not $core) { return $null }
    try { return [version]$core } catch { return $null }
}

function Compare-AppVersion {
    param([string]$Current, [string]$Other)
    $c = ConvertTo-ComparableVersion $Current
    $o = ConvertTo-ComparableVersion $Other
    # $null means "cannot compare". Callers must not treat that as equal —
    # in PowerShell `$null -lt 0` is true, which would look like an update.
    if ($null -eq $c -or $null -eq $o) { return $null }
    return $c.CompareTo($o)
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
    if ($null -eq $cmp) {
        if (-not $Silent) {
            Write-Info "Update check: release version could not be compared"
        }
        return [pscustomobject]@{
            Status  = 'Unavailable'
            Release = $rel
        }
    }
    if ($cmp -lt 0) {
        return [pscustomobject]@{
            Status  = 'UpdateAvailable'
            Release = $rel
        }
    }
    if ($cmp -gt 0) {
        if (-not $Silent) {
            Write-Info ("Local build is newer than GitHub (v{0} > {1})" -f $Script:AppVersion, $rel.Tag)
        }
        return [pscustomobject]@{
            Status  = 'NewerThanRelease'
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

    # Prefer published .sha256 file (same order as Get.ps1), then GitHub asset digest
    $expected = $null
    if ($Release.Sha256Url) {
        Write-Info "Fetching release checksum..."
        Set-UiStatusText "Verifying checksum..."
        Pump-Ui
        $sumPath = Join-Path $work 'expected.sha256'
        $sumDl = Invoke-WithUiWait -Activity "Downloading checksum" -TimeoutSec 60 -ArgumentList @($Release.Sha256Url, $sumPath) -ScriptBlock {
            param([string]$Url, [string]$OutFile)
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "PC-Maintenance-Kit")
                $wc.DownloadFile($Url, $OutFile)
                if (Test-Path -LiteralPath $OutFile) { "OK" } else { "ERR:missing checksum file" }
            } catch {
                "ERR:" + $_.Exception.Message
            }
        }
        $sumText = Get-AsyncResultText $sumDl
        if ($sumText -eq "OK") {
            $expected = Get-ExpectedSha256Text (Get-Content -LiteralPath $sumPath -Raw -EA SilentlyContinue)
        } else {
            Write-Warn "Could not download checksum file; trying release digest"
        }
    }
    if (-not $expected) {
        if ($Release.DigestSha256) { $expected = $Release.DigestSha256 }
        elseif ($Release.ExpectedSha256) { $expected = $Release.ExpectedSha256 }
    }

    if (-not $expected) {
        throw "Refusing to install update: no SHA256 checksum was published for this release."
    }

    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw ("SHA256 mismatch.`n  expected: {0}`n  actual:   {1}" -f $expected, $actual)
    }
    Write-Ok ("SHA256 OK  {0}" -f $actual)

    Write-Info "Extracting update..."
    Set-UiStatusText "Extracting update..."
    Pump-Ui
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force

    $payloadRoot = Resolve-KitPayloadRoot -Extract $extract
    if (-not $payloadRoot) {
        throw "Update ZIP is missing PC-Maintenance.ps1 next to lib\Core.ps1"
    }
    Assert-KitScriptsAuthenticode -Folder $payloadRoot
    if (-not (Test-KitPayloadHealthy -Root $payloadRoot)) {
        throw "Update payload failed its health check"
    }

    $applyPs1 = Join-Path $work "Apply-Update.ps1"
    $startBat = Join-Path $Script:AppRoot "Start.bat"
    # Snapshot lives beside the install (never inside it, or robocopy would recurse into itself)
    $backupRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }
    $backupDir = Join-Path $backupRoot 'PC-Maintenance-Kit-backup'
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
`$backup = @'
$backupDir
'@

function Start-InstalledApp {
    param([string]`$Root, [string]`$Bat)
    if (Test-Path -LiteralPath `$Bat) {
        Start-Process -FilePath `$Bat -WorkingDirectory `$Root
        return
    }
    `$ps1 = Join-Path `$Root 'PC-Maintenance.ps1'
    `$ps = Join-Path `$env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath `$ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',`$ps1,'-Mode','Gui') -WorkingDirectory `$Root
}

function Test-InstallHealthy {
    # A half-copied or corrupted install will not parse - cheap, offline health gate
    param([string]`$Root)
    try {
        `$entry = Join-Path `$Root 'PC-Maintenance.ps1'
        if (-not (Test-Path -LiteralPath `$entry)) { return `$false }
        `$files = New-Object System.Collections.Generic.List[string]
        [void]`$files.Add(`$entry)
        `$libDir = Join-Path `$Root 'lib'
        if (Test-Path -LiteralPath `$libDir) {
            Get-ChildItem -LiteralPath `$libDir -Filter *.ps1 -File -EA SilentlyContinue | ForEach-Object {
                [void]`$files.Add(`$_.FullName)
            }
        }
        if (`$files.Count -lt 2) { return `$false }
        foreach (`$f in `$files) {
            `$errs = `$null
            `$toks = `$null
            [void][System.Management.Automation.Language.Parser]::ParseFile(`$f, [ref]`$toks, [ref]`$errs)
            if (`$errs -and `$errs.Count -gt 0) { return `$false }
        }
        return `$true
    } catch {
        return `$false
    }
}

`$rc = Join-Path `$env:SystemRoot 'System32\robocopy.exe'
`$errDir = Join-Path `$env:TEMP 'PC-Maintenance-Kit'

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

    # Snapshot the working install first so a bad release can always be undone
    if (Test-Path -LiteralPath `$backup) {
        Remove-Item -LiteralPath `$backup -Recurse -Force -EA SilentlyContinue
    }
    New-Item -ItemType Directory -Path `$backup -Force | Out-Null
    & `$rc `$target `$backup /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if (`$LASTEXITCODE -ge 8) { throw "Could not back up current install (robocopy `$LASTEXITCODE)" }

    # robocopy avoids Copy-Item nesting bug (lib -> lib\lib when destination exists)
    & `$rc `$source `$target /E /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    `$code = `$LASTEXITCODE
    if (`$code -ge 8) { throw "robocopy failed with code `$code" }

    # Purge scripts removed from the new release (robocopy /E does not delete extras)
    function Remove-StaleScripts {
        param([string]`$SrcRoot, [string]`$DstRoot)
        if (-not (Test-Path -LiteralPath `$SrcRoot)) { return }
        if (-not (Test-Path -LiteralPath `$DstRoot)) { return }
        Get-ChildItem -LiteralPath `$DstRoot -File -Filter '*.ps1' -EA SilentlyContinue | ForEach-Object {
            `$peer = Join-Path `$SrcRoot `$_.Name
            if (-not (Test-Path -LiteralPath `$peer)) {
                Remove-Item -LiteralPath `$_.FullName -Force -EA SilentlyContinue
            }
        }
    }
    Remove-StaleScripts -SrcRoot `$source -DstRoot `$target
    Remove-StaleScripts -SrcRoot (Join-Path `$source 'lib') -DstRoot (Join-Path `$target 'lib')

    if (-not (Test-InstallHealthy -Root `$target)) {
        throw "Updated install failed its health check"
    }

    Start-InstalledApp -Root `$target -Bat `$startBat
} catch {
    if (-not (Test-Path `$errDir)) { New-Item -ItemType Directory -Path `$errDir -Force | Out-Null }
    `$log = Join-Path `$errDir 'update-error.log'
    `$_ | Out-File `$log -Encoding utf8

    # Roll back so the user is never left with a broken install
    if (Test-Path -LiteralPath (Join-Path `$backup 'PC-Maintenance.ps1')) {
        try {
            & `$rc `$backup `$target /E /IS /IT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
            if (`$LASTEXITCODE -lt 8 -and (Test-InstallHealthy -Root `$target)) {
                "Rolled back to the previous version." | Out-File `$log -Encoding utf8 -Append
            } else {
                "Rollback failed. Backup kept at: `$backup" | Out-File `$log -Encoding utf8 -Append
            }
        } catch {
            "Rollback threw: `$(`$_.Exception.Message)" | Out-File `$log -Encoding utf8 -Append
        }
    }
    try { Start-InstalledApp -Root `$target -Bat `$startBat } catch { }
} finally {
    Start-Sleep -Seconds 2
    try { Remove-Item -LiteralPath `$work -Recurse -Force -EA SilentlyContinue } catch { }
}
"@
    Set-Content -LiteralPath $applyPs1 -Value $applyBody -Encoding UTF8

    Write-Info ("Backing up current install to {0}" -f $backupDir)
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
        $r = Show-UiMessageBox `
            -Text $msg `
            -Caption "PC Maintenance Kit - Update" `
            -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
            -Icon ([System.Windows.Forms.MessageBoxIcon]::Information)
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        if ($hasZip) {
            try {
                Invoke-AppSelfUpdate -Release $Release
            } catch {
                $Script:ExitAfterUpdate = $false
                Write-Fail $_.Exception.Message
                $fallback = Show-UiMessageBox `
                    -Text ("Automatic update failed:`n{0}`n`nOpen GitHub releases page instead?" -f $_.Exception.Message) `
                    -Caption "PC Maintenance Kit - Update" `
                    -Buttons ([System.Windows.Forms.MessageBoxButtons]::YesNo) `
                    -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
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
    $cliArgs = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$scriptPath`" -Mode Cli"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps
    $psi.Arguments = $cliArgs
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
