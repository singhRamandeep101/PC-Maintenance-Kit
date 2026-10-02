#Requires -Version 5.1
# Gaming Optimization Score  -  config/setup scoring (not a hardware benchmark).

$Script:OptimizationScoreCache = $null
$Script:OptimizationScoreCacheUtc = [datetime]::MinValue

function New-OptimizationCheck {
    param(
        [string]$Id,
        [string]$Category,
        [ValidateSet('Good','Warn','Bad','Unknown')]$Status,
        [double]$Points,
        [double]$Max,
        [string]$Title,
        [string]$Detail,
        [string]$FixHint = '',
        [ValidateSet('GamingOptimize','OpenStorage','CopyRamTip','OpenStartup','OpenServices','OpenTasks','OpenDisplay','OpenSecurity','None')]$FixAction = 'None'
    )
    return [pscustomobject]@{
        Id        = $Id
        Category  = $Category
        Status    = $Status
        Points    = [math]::Round($Points, 2)
        Max       = [math]::Round($Max, 2)
        Title     = $Title
        Detail    = $Detail
        FixHint   = $FixHint
        FixAction = $FixAction
    }
}

function Get-VideoControllers {
    param([switch]$Refresh)
    # Device summary and the score both need this list. One CIM query fills both.
    if (-not $Refresh -and $null -ne $Script:VideoControllerCache -and (([datetime]::UtcNow - $Script:VideoControllerCache.Utc).TotalSeconds -lt 600)) {
        return @($Script:VideoControllerCache.Items | Where-Object { $_ })
    }
    $list = New-Object System.Collections.Generic.List[object]
    try {
        $found = @(Get-CimInstance Win32_VideoController -EA SilentlyContinue |
            Where-Object { $_.Name -and $_.Name -notmatch 'Basic|Remote|Microsoft Basic' } |
            Sort-Object { if ($_.AdapterRAM -gt 0) { -$_.AdapterRAM } else { 0 } })
        foreach ($g in $found) { if ($g) { [void]$list.Add($g) } }
    } catch { }
    $Script:VideoControllerCache = @{ Items = $list.ToArray(); Utc = [datetime]::UtcNow }
    return @($Script:VideoControllerCache.Items)
}

function Get-PrimaryVideoController {
    param([switch]$Refresh)
    $gpus = @(Get-VideoControllers -Refresh:$Refresh)
    if ($gpus.Count -gt 0) { return $gpus[0] }
    if (-not $Refresh -and $null -ne $Script:PrimaryVideoCache -and (([datetime]::UtcNow - $Script:PrimaryVideoCacheUtc).TotalSeconds -lt 600)) {
        return $Script:PrimaryVideoCache
    }
    $vc = $null
    try { $vc = Get-CimInstance Win32_VideoController -EA SilentlyContinue | Select-Object -First 1 } catch { $vc = $null }
    $Script:PrimaryVideoCache = $vc
    $Script:PrimaryVideoCacheUtc = [datetime]::UtcNow
    return $vc
}

function Get-DisplayRefreshInfo {
    param($VideoController = $null)
    $info = [pscustomobject]@{
        CurrentHz = $null
        MaxHz     = $null
        Adapter   = $null
    }
    try {
        $vc = $VideoController
        if (-not $vc) { $vc = Get-PrimaryVideoController }
        if (-not $vc) { return $info }
        $info.Adapter = [string]$vc.Name
        if ($vc.CurrentRefreshRate -and [int]$vc.CurrentRefreshRate -gt 0) {
            $info.CurrentHz = [int]$vc.CurrentRefreshRate
        }
        if ($vc.MaxRefreshRate -and [int]$vc.MaxRefreshRate -gt 0) {
            $info.MaxHz = [int]$vc.MaxRefreshRate
        }
    } catch { }
    return $info
}

function Get-GpuDriverInfo {
    param($VideoController = $null)
    $info = [pscustomobject]@{
        Name        = $null
        Version     = $null
        DriverDate  = $null
        AgeDays     = $null
        IsBasic     = $false
        VendorOk    = $false
    }
    try {
        $vc = $VideoController
        if (-not $vc) { $vc = Get-PrimaryVideoController }
        if (-not $vc) { return $info }
        $info.Name = [string]$vc.Name
        $info.Version = [string]$vc.DriverVersion
        $info.IsBasic = ($info.Name -match 'Basic Display|Microsoft Basic')
        $info.VendorOk = (-not $info.IsBasic) -and ($info.Name -match 'NVIDIA|AMD|Radeon|GeForce|Intel|Arc')
        if ($vc.DriverDate) {
            try {
                # CIM DriverDate is often like 20240101120000.000000-000
                $raw = [string]$vc.DriverDate
                $dt = $null
                if ($raw -match '^(\d{14})') {
                    $dt = [datetime]::ParseExact($Matches[1], 'yyyyMMddHHmmss', $null)
                } else {
                    $dt = [datetime]$vc.DriverDate
                }
                $info.DriverDate = $dt
                $info.AgeDays = [int]([datetime]::UtcNow - $dt.ToUniversalTime()).TotalDays
            } catch { }
        }
    } catch { }
    return $info
}

function Test-StartupApprovedEnabled {
    param($Bytes)
    # No StartupApproved value means Windows still launches it.
    # An odd first byte (1, 3, 7) is the off switch in Settings > Startup apps.
    if ($null -eq $Bytes) { return $true }
    $first = $null
    if ($Bytes -is [System.Array]) {
        $items = @($Bytes)
        if ($items.Count -lt 1) { return $true }
        $first = [int]$items[0]
    } else {
        try { $first = [int]$Bytes } catch { return $true }
    }
    return (($first -band 1) -eq 0)
}

function Get-StartupApprovedBytes {
    param([string]$Key, [string]$Name)
    if (-not $Key -or -not $Name -or -not (Test-Path -LiteralPath $Key)) { return $null }
    try {
        # GetValue is literal. Get-ItemProperty -Name treats [ and * as wildcards.
        $item = Get-Item -LiteralPath $Key -EA Stop
        return $item.GetValue($Name, $null)
    } catch { }
    return $null
}

function Select-StartupAppWinners {
    param([object[]]$Items)
    $found = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    # Index the array. foreach over PSCustomObject rows throws
    # "Argument types do not match" in Windows PowerShell 5.1.
    $count = 0
    if ($null -ne $Items) { $count = $Items.Count }
    for ($i = 0; $i -lt $count; $i++) {
        $item = $Items[$i]
        if (-not $item) { continue }
        $clean = ([string]$item.Name).Trim()
        if (-not $clean) { continue }
        $key = $clean.ToLowerInvariant()
        $enabled = [bool]$item.Enabled
        if ($seen.ContainsKey($key)) {
            # A disabled Run entry must not hide the same app starting from
            # the Startup folder or a Store task.
            if ($enabled -and -not $seen[$key].Enabled) {
                $seen[$key].Enabled = $true
                if ($item.Source) { $seen[$key].Source = [string]$item.Source }
            }
            continue
        }
        $row = [pscustomobject]@{
            Name    = $clean
            Enabled = $enabled
            Source  = [string]$item.Source
        }
        $seen[$key] = $row
        [void]$found.Add($row)
    }
    return @($found.ToArray())
}

function Format-StartupPackageName {
    param([string]$Family, [string]$Task)
    if ($Task -and $Task -notmatch '^[0-9a-fA-F-]{36}$') { return $Task }
    $base = [string]$Family
    $under = $base.IndexOf('_')
    if ($under -gt 0) { $base = $base.Substring(0, $under) }
    $dot = $base.LastIndexOf('.')
    if ($dot -ge 0 -and $dot -lt ($base.Length - 1)) { return $base.Substring($dot + 1) }
    if ($base) { return $base }
    return $Task
}

function Get-StartupApps {
    $raw = New-Object System.Collections.Generic.List[object]

    function Add-StartupApp([string]$Name, [bool]$Enabled, [string]$Source) {
        $clean = ([string]$Name).Trim()
        if (-not $clean) { return }
        [void]$raw.Add([pscustomobject]@{
            Name    = $clean
            Enabled = $Enabled
            Source  = $Source
        })
    }

    function Test-StartupRunOn {
        param([string[]]$ApprovedKeys, [string]$Name)
        foreach ($key in @($ApprovedKeys)) {
            $bytes = Get-StartupApprovedBytes -Key $key -Name $Name
            if ($null -eq $bytes) { continue }
            if (-not (Test-StartupApprovedEnabled $bytes)) { return $false }
        }
        return $true
    }

    $runSources = @(
        @{ Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'); Source = 'User' },
        @{ Run = 'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'); Source = 'User' },
        @{ Run = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'); Source = 'Machine' },
        @{ Run = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'); Source = 'Machine' }
    )
    foreach ($src in $runSources) {
        try {
            if (-not (Test-Path -LiteralPath $src.Run)) { continue }
            $props = Get-ItemProperty -Path $src.Run -EA SilentlyContinue
            if (-not $props) { continue }
            foreach ($prop in @($props.PSObject.Properties)) {
                if ($prop.Name -like 'PS*') { continue }
                $on = Test-StartupRunOn -ApprovedKeys $src.Approved -Name $prop.Name
                Add-StartupApp $prop.Name $on $src.Source
            }
        } catch { }
    }

    $folders = @(
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'); Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Source = 'User folder' },
        @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); Approved = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Source = 'Common folder' }
    )
    foreach ($folder in $folders) {
        try {
            if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
            Get-ChildItem -LiteralPath $folder.Path -File -EA SilentlyContinue | ForEach-Object {
                if ($_.Name -eq 'desktop.ini') { return }
                $leaf = $_.BaseName
                $bytes = Get-StartupApprovedBytes -Key $folder.Approved -Name $_.Name
                if ($null -eq $bytes) { $bytes = Get-StartupApprovedBytes -Key $folder.Approved -Name $leaf }
                Add-StartupApp $leaf (Test-StartupApprovedEnabled $bytes) $folder.Source
            }
        } catch { }
    }

    $appRoot = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
    $skipKids = @('HAM', 'PSR', 'Schemas', 'SplashScreen', 'PersistedPickerData')
    try {
        if (Test-Path -LiteralPath $appRoot) {
            Get-ChildItem -LiteralPath $appRoot -EA SilentlyContinue | ForEach-Object {
                $family = $_.PSChildName
                Get-ChildItem -LiteralPath $_.PSPath -EA SilentlyContinue | ForEach-Object {
                    if ($skipKids -contains $_.PSChildName) { return }
                    $taskProp = $null
                    try { $taskProp = Get-ItemProperty -LiteralPath $_.PSPath -EA SilentlyContinue } catch { }
                    if (-not $taskProp -or -not $taskProp.PSObject.Properties['UserEnabledStartupOnce']) { return }
                    if (-not $taskProp.PSObject.Properties['State']) { return }
                    $state = $taskProp.State
                    $on = ($state -eq 2 -or $state -eq 4)
                    $label = Format-StartupPackageName -Family $family -Task $_.PSChildName
                    Add-StartupApp $label $on 'Windows app'
                }
            }
        }
    } catch { }

    return @(Select-StartupAppWinners $raw | Sort-Object Name)
}

function Get-StartupEntryCount {
    return @(@(Get-StartupApps) | Where-Object { $_.Enabled }).Count
}

function Test-ServicePathIsWindows([string]$PathName) {
    if ([string]::IsNullOrWhiteSpace($PathName)) { return $true }
    $path = $PathName.Trim()
    if ($path.StartsWith('"')) {
        $end = $path.IndexOf('"', 1)
        if ($end -gt 1) { $path = $path.Substring(1, $end - 1) }
        else { $path = $path.Trim('"') }
    }
    $root = $env:SystemRoot
    if ([string]::IsNullOrWhiteSpace($root)) { $root = 'C:\Windows' }
    $rootFull = $root
    try { $rootFull = [System.IO.Path]::GetFullPath($root) } catch { }
    $prefix = $rootFull.TrimEnd('\') + '\'
    return $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-StartupTokenBoundary {
    param([string]$Haystack, [string]$Needle)
    if (-not $Haystack -or -not $Needle) { return $false }
    $idx = $Haystack.IndexOf($Needle)
    while ($idx -ge 0) {
        $beforeOk = ($idx -eq 0) -or ($Haystack[$idx - 1] -notmatch '[a-z0-9]')
        $after = $idx + $Needle.Length
        $afterOk = ($after -ge $Haystack.Length) -or ($Haystack[$after] -notmatch '[a-z0-9]')
        if ($beforeOk -and $afterOk) { return $true }
        if (($idx + 1) -ge $Haystack.Length) { break }
        $idx = $Haystack.IndexOf($Needle, $idx + 1)
    }
    return $false
}

function Test-StartupServiceNameMatch {
    param(
        [string]$AppName,
        [string]$ServiceName,
        [string]$DisplayName,
        [string]$PathName
    )
    # Whole name or a path segment. "Edge" must not match "SomeEdgeHelper",
    # and "Update" must not match "WindowsUpdate".
    $app = ([string]$AppName).Trim()
    if ($app.Length -lt 4) { return $false }
    $appKey = $app.ToLowerInvariant()
    $dispKey = ([string]$DisplayName).Trim().ToLowerInvariant()
    $svcKey = ([string]$ServiceName).Trim().ToLowerInvariant()
    if ($dispKey -eq $appKey -or $svcKey -eq $appKey) { return $true }
    if ($dispKey.Length -ge 4 -and (Test-StartupTokenBoundary $dispKey $appKey)) { return $true }
    $pathOnly = [string]$PathName
    if ($pathOnly.StartsWith('"')) {
        $end = $pathOnly.IndexOf('"', 1)
        if ($end -gt 1) { $pathOnly = $pathOnly.Substring(1, $end - 1) }
    }
    $segments = @($pathOnly.ToLowerInvariant() -split '[\\/]+')
    foreach ($seg in $segments) {
        if (-not $seg) { continue }
        $leaf = $seg
        if ($leaf.EndsWith('.exe') -or $leaf.EndsWith('.dll')) {
            $leaf = $leaf.Substring(0, $leaf.Length - 4)
        }
        if ($leaf -eq $appKey) { return $true }
    }
    return $false
}

function Resolve-ServiceBinaryPath {
    param([string]$ServiceName, [string]$PathName)
    $path = [string]$PathName
    if ($path -notmatch 'svchost\.exe') { return $path }
    if (-not $ServiceName) { return $path }
    $safeName = $ServiceName.Trim()
    if ($safeName -notmatch '^[A-Za-z0-9_.-]+$') { return $path }
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$safeName\Parameters"
    try {
        $item = Get-Item -LiteralPath $key -EA Stop
        $dll = $item.GetValue('ServiceDll', $null)
        if ($dll) { return [Environment]::ExpandEnvironmentVariables([string]$dll) }
    } catch { }
    return $path
}

function Select-StartupServiceHolds {
    param([object[]]$Apps, [object[]]$Services)
    # A Startup apps toggle does not stop an automatic service outside Windows.
    $found = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $appCount = 0
    if ($null -ne $Apps) { $appCount = $Apps.Count }
    $svcCount = 0
    if ($null -ne $Services) { $svcCount = $Services.Count }
    for ($i = 0; $i -lt $appCount; $i++) {
        $app = $Apps[$i]
        if (-not $app -or $app.Enabled) { continue }
        $name = ([string]$app.Name).Trim()
        if (-not $name) { continue }
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        for ($j = 0; $j -lt $svcCount; $j++) {
            $svc = $Services[$j]
            if (-not $svc) { continue }
            if (Test-ServicePathIsWindows ([string]$svc.PathName)) { continue }
            if (Test-StartupServiceNameMatch -AppName $name -ServiceName ([string]$svc.Name) -DisplayName ([string]$svc.DisplayName) -PathName ([string]$svc.PathName)) {
                $seen[$key] = $true
                [void]$found.Add($name)
                break
            }
        }
    }
    return @($found.ToArray())
}

function Get-AutoStartServices {
    param([switch]$Refresh)
    if (-not $Refresh -and $Script:AutoServiceCache -and (([datetime]::UtcNow - $Script:AutoServiceCacheUtc).TotalSeconds -lt 10)) {
        return @($Script:AutoServiceCache)
    }
    $found = New-Object System.Collections.Generic.List[object]
    try {
        Get-CimInstance -ClassName Win32_Service -Filter "StartMode='Auto'" -EA Stop | ForEach-Object {
            $image = Resolve-ServiceBinaryPath -ServiceName ([string]$_.Name) -PathName ([string]$_.PathName)
            [void]$found.Add([pscustomobject]@{
                Name        = [string]$_.Name
                DisplayName = [string]$_.DisplayName
                PathName    = [string]$image
            })
        }
    } catch { }
    $Script:AutoServiceCache = @($found.ToArray())
    $Script:AutoServiceCacheUtc = [datetime]::UtcNow
    return @($Script:AutoServiceCache)
}

function Get-StartupServiceHolds {
    param($Apps, [switch]$Refresh)
    return @(Select-StartupServiceHolds -Apps $Apps -Services (Get-AutoStartServices -Refresh:$Refresh))
}

function Format-StartupServiceHoldList {
    param([string[]]$Names, [int]$MaxNames = 4)
    $count = 0
    if ($null -ne $Names) { $count = $Names.Count }
    if ($count -lt 1) { return '' }
    $shown = New-Object System.Collections.Generic.List[string]
    $limit = $MaxNames
    if ($limit -gt $count) { $limit = $count }
    for ($i = 0; $i -lt $limit; $i++) {
        [void]$shown.Add([string]$Names[$i])
    }
    $text = ($shown -join ', ')
    $extra = $count - $limit
    if ($extra -gt 0) { $text = ("{0}, and {1} more" -f $text, $extra) }
    return ("Still starts as a service: {0}" -f $text)
}

function Select-ExtraLogonTaskNames {
    param([object[]]$Tasks, [object[]]$Apps, [string]$SkipName)
    $enabled = @{}
    $appCount = 0
    if ($null -ne $Apps) { $appCount = $Apps.Count }
    for ($i = 0; $i -lt $appCount; $i++) {
        $app = $Apps[$i]
        if (-not $app -or -not $app.Enabled) { continue }
        $key = ([string]$app.Name).Trim().ToLowerInvariant()
        if ($key) { $enabled[$key] = $true }
    }
    $found = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $taskCount = 0
    if ($null -ne $Tasks) { $taskCount = $Tasks.Count }
    for ($i = 0; $i -lt $taskCount; $i++) {
        $task = $Tasks[$i]
        if (-not $task -or -not $task.Enabled -or -not $task.Logon) { continue }
        $path = [string]$task.Path
        if ($path.StartsWith('\Microsoft\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $name = ([string]$task.Name).Trim()
        if (-not $name) { continue }
        if ($SkipName -and ($name -eq $SkipName)) { continue }
        if (-not (Test-ReadableSignInName $name)) { continue }
        $key = $name.ToLowerInvariant()
        if ($enabled.ContainsKey($key) -or $seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$found.Add($name)
    }
    return @($found.ToArray())
}

function Get-ExtraLogonTaskNames {
    param($Apps, [switch]$Refresh)
    if (-not $Refresh -and $Script:LogonTaskCache -and (([datetime]::UtcNow - $Script:LogonTaskCacheUtc).TotalSeconds -lt 10)) {
        return @(Select-ExtraLogonTaskNames -Tasks $Script:LogonTaskCache -Apps $Apps -SkipName $Script:LogonTaskSkipName)
    }
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        Get-ScheduledTask -EA Stop | ForEach-Object {
            $logon = $false
            try {
                foreach ($trigger in @($_.Triggers)) {
                    if (-not $trigger) { continue }
                    $class = ''
                    try { $class = [string]$trigger.CimClass.CimClassName } catch { $class = '' }
                    if ($class -match 'Logon') { $logon = $true; break }
                }
            } catch { }
            $enabled = $false
            try { $enabled = ([string]$_.State -ne 'Disabled') } catch { }
            [void]$rows.Add([pscustomobject]@{
                Name    = [string]$_.TaskName
                Path    = [string]$_.TaskPath
                Enabled = [bool]$enabled
                Logon   = [bool]$logon
            })
        }
    } catch { }
    $skip = 'PC Maintenance Kit - Weekly Full'
    if ($Script:WeeklyCareTaskName) { $skip = [string]$Script:WeeklyCareTaskName }
    $Script:LogonTaskCache = @($rows.ToArray())
    $Script:LogonTaskCacheUtc = [datetime]::UtcNow
    $Script:LogonTaskSkipName = $skip
    return @(Select-ExtraLogonTaskNames -Tasks $Script:LogonTaskCache -Apps $Apps -SkipName $skip)
}

function Test-ReadableSignInName([string]$Name) {
    # Scheduled tasks are often ids like cua-driver-serve or StartDVR.
    # A name a person can read has a space: "Steam Client".
    $n = ([string]$Name).Trim()
    if ($n.Length -lt 4) { return $false }
    if ($n -notmatch '\s') { return $false }
    if ($n -match '[\\/_{}@]|-{2,}|\d{4,}') { return $false }
    return $true
}

function Format-LogonTaskList {
    param([string[]]$Names, [int]$MaxNames = 4)
    $count = 0
    if ($null -ne $Names) { $count = $Names.Count }
    if ($count -lt 1) { return '' }
    $shown = New-Object System.Collections.Generic.List[string]
    $limit = $MaxNames
    if ($limit -gt $count) { $limit = $count }
    for ($i = 0; $i -lt $limit; $i++) {
        [void]$shown.Add([string]$Names[$i])
    }
    $text = ($shown -join ', ')
    $extra = $count - $limit
    if ($extra -gt 0) { $text = ("{0}, and {1} more" -f $text, $extra) }
    return ("Also signs in: {0}" -f $text)
}

function Get-StartupBackgroundJudgement {
    param(
        [bool]$ReadOk,
        [int]$EnabledCount,
        [string]$AppList,
        [string]$HoldText,
        [string]$LogonText,
        [double]$MaxPoints = 100
    )
    if (-not $ReadOk) {
        return [pscustomobject]@{
            Points = $MaxPoints
            Status = 'Unknown'
            Detail = 'Startup apps could not be read'
            Hint   = ''
            Fix    = 'None'
        }
    }
    $score = $MaxPoints
    $status = 'Good'
    $detail = [string]$AppList
    $fix = 'None'
    $hint = ''
    if ($EnabledCount -le 5) {
        $score = $MaxPoints
        $status = 'Good'
    } elseif ($EnabledCount -le 12) {
        $score = $MaxPoints * 0.55
        $status = 'Warn'
        $detail = ("{0}  -  turn off the ones you don't need" -f $AppList)
        $fix = 'OpenStartup'
        $hint = $detail
    } else {
        $score = $MaxPoints * 0.2
        $status = 'Bad'
        $detail = ("{0}  -  heavy background load" -f $AppList)
        $fix = 'OpenStartup'
        $hint = $detail
    }
    if ($HoldText) {
        if ($status -eq 'Good') {
            $score = $MaxPoints * 0.55
            $status = 'Warn'
        }
        $detail = ("{0}`r`n{1}" -f $AppList, $HoldText)
        $fix = 'OpenServices'
        $hint = $HoldText
    }
    if ($LogonText) {
        $detail = $detail + "`r`n" + $LogonText
        if ($status -eq 'Good') {
            $score = $MaxPoints * 0.7
            $status = 'Warn'
        }
        if ($fix -eq 'None') {
            $fix = 'OpenStartup'
            $hint = 'Extra programs sign in with Windows. Open Startup apps and turn off what you do not use.'
        }
    }
    return [pscustomobject]@{
        Points = $score
        Status = $status
        Detail = $detail
        Hint   = $hint
        Fix    = $fix
    }
}

function Format-StartupAppList {
    param($Apps, [int]$MaxNames = 6)
    $enabled = @($Apps | Where-Object { $_.Enabled })
    if ($enabled.Count -eq 0) { return 'Nothing is set to start with Windows' }
    $names = @($enabled | ForEach-Object { [string]$_.Name })
    $shown = @($names | Select-Object -First $MaxNames)
    $text = ($shown -join ', ')
    $extra = $names.Count - $shown.Count
    if ($extra -gt 0) { $text = ("{0}, and {1} more" -f $text, $extra) }
    $verb = 'start'
    if ($enabled.Count -eq 1) { $verb = 'starts' }
    return ("{0} {1} with Windows: {2}" -f $enabled.Count, $verb, $text)
}

function Get-HagsEnabled {
    try {
        $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -EA SilentlyContinue).HwSchMode
        if ($null -eq $v) { return $null }
        return ([int]$v -eq 2)
    } catch {
        return $null
    }
}

function Get-SecurityScanFreshness {
    param(
        $LastScan,
        [bool]$Known = $true,
        [int]$MaxAgeDays = 20,
        [double]$MaxPoints = 100
    )
    # A missed read stays full points. Only a scan older than the window,
    # or no scan on record, marks this check Bad.
    if (-not $Known) {
        return [pscustomobject]@{
            Points = $MaxPoints
            Status = 'Unknown'
            Detail = 'Defender scan time could not be read'
            Hint   = ''
        }
    }
    $when = $null
    if ($LastScan -is [datetime] -and $LastScan.Year -ge 2000) { $when = $LastScan }
    if (-not $when) {
        return [pscustomobject]@{
            Points = 0
            Status = 'Bad'
            Detail = 'No Defender scan on record'
            Hint   = 'Run a scan in Windows Security'
        }
    }
    $age = [int]([datetime]::Now - $when).TotalDays
    if ($age -lt 0) { $age = 0 }
    if ($age -le $MaxAgeDays) {
        $whenText = 'today'
        if ($age -eq 1) { $whenText = '1 day ago' }
        elseif ($age -gt 1) { $whenText = ("{0} days ago" -f $age) }
        return [pscustomobject]@{
            Points = $MaxPoints
            Status = 'Good'
            Detail = ("Last Defender scan was {0}" -f $whenText)
            Hint   = ''
        }
    }
    return [pscustomobject]@{
        Points = 0
        Status = 'Bad'
        Detail = ("Last Defender scan was {0} days ago" -f $age)
        Hint   = 'Run a scan in Windows Security'
    }
}

function Get-OptimizationGrade([int]$Score) {
    if ($Score -ge 85) { return 'Excellent' }
    if ($Score -ge 70) { return 'Good' }
    if ($Score -ge 50) { return 'Needs work' }
    return 'Critical'
}

function Get-DisplayedOptimizationScore {
    param(
        [int]$WeightedScore,
        [string]$ScanStatus
    )
    # Category weights stay as they are. A scan older than 20 days still
    # holds the headline at Needs work, so a tuned PC cannot stay Excellent.
    $score = $WeightedScore
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }
    $weighted = $score
    $note = ''
    if ($ScanStatus -eq 'Bad' -and $score -gt 69) {
        $score = 69
        $note = ("Held at Needs work because the last Defender scan is older than 20 days. Weighted total was {0}." -f $weighted)
    }
    return [pscustomobject]@{
        Score    = $score
        Weighted = $weighted
        Note     = $note
    }
}

function Get-BiggestScoreLimiter {
    param([object[]]$Categories)
    # Points lost = weight times how far the category is from 100.
    # A small category at a low percent must not outrank a heavier one.
    $bestName = 'None'
    $bestImpact = -1.0
    $count = 0
    if ($null -ne $Categories) { $count = $Categories.Count }
    for ($i = 0; $i -lt $count; $i++) {
        $cat = $Categories[$i]
        if (-not $cat) { continue }
        $impact = [double]$cat.Weight * (100.0 - [double]$cat.Score)
        if ($impact -gt $bestImpact) {
            $bestImpact = $impact
            $bestName = [string]$cat.Name
        }
    }
    return $bestName
}

function Get-DiskMediaScore {
    param(
        [string]$MediaType,
        [string]$FriendlyName,
        [double]$MaxPoints = 40
    )
    $name = if ([string]::IsNullOrWhiteSpace($FriendlyName)) { 'disk' } else { $FriendlyName }
    if ($MediaType -match 'SSD') {
        return [pscustomobject]@{
            Points = $MaxPoints
            Status = 'Good'
            Detail = "System disk: $name ($MediaType)"
            Hint   = ''
        }
    }
    if ($MediaType -match 'HDD') {
        return [pscustomobject]@{
            Points = 0
            Status = 'Bad'
            Detail = "System disk is HDD ($name)  -  slow loads and stutter risk"
            Hint   = 'Move Windows/games to an SSD when you can'
        }
    }
    if ([string]::IsNullOrWhiteSpace($MediaType) -or $MediaType -match 'Unspecified') {
        return [pscustomobject]@{
            Points = 0
            Status = 'Unknown'
            Detail = "System disk media type not reported ($name)"
            Hint   = ''
        }
    }
    return [pscustomobject]@{
        Points = ($MaxPoints * 0.6)
        Status = 'Warn'
        Detail = "System disk media: $MediaType"
        Hint   = ''
    }
}

function Get-GamingOptimizationScore {
    param([switch]$Refresh)

    # Short on purpose. Hardware probes keep their own longer cache.
    if (-not $Refresh -and $Script:OptimizationScoreCache -and (([datetime]::UtcNow - $Script:OptimizationScoreCacheUtc).TotalSeconds -lt 10)) {
        return $Script:OptimizationScoreCache
    }

    $checks = New-Object System.Collections.Generic.List[object]
    $s = $null
    $summaryOk = $false
    try {
        $s = Get-DeviceSummary -Refresh:$Refresh
        $summaryOk = $true
    } catch {
        Write-Warn ("Score could not read the device summary: {0}" -f $_.Exception.Message)
    }

    # ---- Storage (weight 0.14) ----
    $mediaPts = 40.0
    $freePts = 40.0
    $healthPts = 20.0
    # Unknown probes start at zero. A failed disk read must not look like a healthy SSD.
    $mediaScore = 0.0
    $freeScore = 0.0
    $healthScore = 0.0
    $mediaStatus = 'Unknown'
    $freeStatus = 'Unknown'
    $healthStatus = 'Unknown'
    $mediaDetail = 'Could not detect system disk media type'
    $freeDetail = 'Could not read free space'
    $healthDetail = 'Could not read disk health'
    $mediaFix = 'None'
    $freeFix = 'None'
    $mediaHint = ''
    $freeHint = ''

    $disk = $null
    try {
        if ($s -and $s.DiskName -and $s.DiskName -ne 'Unknown') {
            $disk = [pscustomobject]@{
                FriendlyName = $s.DiskName
                HealthStatus = $s.DiskHealth
                MediaType    = $s.DiskMediaType
            }
        }
        if (-not $disk -and (Get-Command Get-SystemDisk -EA SilentlyContinue)) {
            $disk = Get-SystemDisk
        }
    } catch {
        Write-Warn ("Score could not read the disk: {0}" -f $_.Exception.Message)
    }

    $mediaType = $null
    if ($disk) {
        $mediaType = [string]$disk.MediaType
        $healthStr = [string]$disk.HealthStatus
        $mediaJudged = Get-DiskMediaScore -MediaType $mediaType -FriendlyName $disk.FriendlyName -MaxPoints $mediaPts
        $mediaScore = $mediaJudged.Points
        $mediaStatus = $mediaJudged.Status
        $mediaDetail = $mediaJudged.Detail
        if ($mediaJudged.Hint) { $mediaHint = $mediaJudged.Hint }

        if ($healthStr -match 'Healthy') {
            $healthScore = $healthPts
            $healthStatus = 'Good'
            $healthDetail = "Disk health: $healthStr"
        } elseif ($healthStr -match 'Warning') {
            $healthScore = $healthPts * 0.4
            $healthStatus = 'Warn'
            $healthDetail = "Disk health: $healthStr"
        } elseif ($healthStr -match 'Unhealthy') {
            $healthScore = 0
            $healthStatus = 'Bad'
            $healthDetail = "Disk health: $healthStr  -  back up and replace soon"
        } else {
            $healthScore = 0
            $healthStatus = 'Unknown'
            $healthDetail = if ([string]::IsNullOrWhiteSpace($healthStr)) { 'Could not read disk health' } else { "Disk health: $healthStr" }
        }
    }

    $freeGb = $null
    if ($s -and $null -ne $s.FreeGb) { $freeGb = [double]$s.FreeGb }
    elseif (Get-Command Get-CFreeGB -EA SilentlyContinue) {
        try { $freeGb = [double](Get-CFreeGB) } catch { }
    }
    $capGb = Get-SystemDriveCapacityGB
    $freePct = $null
    if ($null -ne $freeGb -and $null -ne $capGb -and $capGb -gt 0) {
        $freePct = ($freeGb / $capGb) * 100.0
    }

    if ($null -ne $freeGb) {
        $okByPct = ($null -ne $freePct -and $freePct -ge 20)
        $okByGb = ($freeGb -ge 40)
        $failByPct = ($null -ne $freePct -and $freePct -lt 10)
        $failByGb = ($freeGb -lt 15)

        if ($okByPct -or $okByGb) {
            $freeScore = $freePts
            $freeStatus = 'Good'
            $pctTxt = if ($null -ne $freePct) { ('{0:N0}%' -f $freePct) } else { 'n/a' }
            $freeDetail = ("C: free {0:N1} GB ({1})" -f $freeGb, $pctTxt)
        } elseif ($failByPct -or $failByGb) {
            $freeScore = 0
            $freeStatus = 'Bad'
            $pctTxt = if ($null -ne $freePct) { ('{0:N0}%' -f $freePct) } else { 'n/a' }
            $freeDetail = ("C: only {0:N1} GB free ({1})  -  SSD/OS needs headroom" -f $freeGb, $pctTxt)
            $freeFix = 'OpenStorage'
            $freeHint = 'Free space on C: (cleanup or Storage settings)'
        } else {
            $freeScore = $freePts * 0.5
            $freeStatus = 'Warn'
            $pctTxt = if ($null -ne $freePct) { ('{0:N0}%' -f $freePct) } else { 'n/a' }
            $freeDetail = ("C: {0:N1} GB free ({1})  -  aim for ~20% or 40+ GB" -f $freeGb, $pctTxt)
            $freeFix = 'OpenStorage'
            $freeHint = 'Free more space on C:'
        }
    }

    [void]$checks.Add((New-OptimizationCheck -Id 'storage_media' -Category 'Storage' -Status $mediaStatus `
        -Points $mediaScore -Max $mediaPts -Title 'System drive type' -Detail $mediaDetail `
        -FixHint $mediaHint -FixAction $mediaFix))
    [void]$checks.Add((New-OptimizationCheck -Id 'storage_free' -Category 'Storage' -Status $freeStatus `
        -Points $freeScore -Max $freePts -Title 'Free space on C:' -Detail $freeDetail `
        -FixHint $freeHint -FixAction $freeFix))
    [void]$checks.Add((New-OptimizationCheck -Id 'storage_health' -Category 'Storage' -Status $healthStatus `
        -Points $healthScore -Max $healthPts -Title 'Disk health' -Detail $healthDetail))

    # ---- Memory (weight 0.09) ----
    $memCapMax = 50.0
    $memChMax = 50.0
    $capScore = 0.0
    $chScore = 0.0
    $capStatus = 'Unknown'
    $chStatus = 'Unknown'
    $capDetail = 'RAM capacity unknown'
    $chDetail = 'Channel config unknown'
    $chFix = 'None'
    $chHint = ''

    $ramGb = $null
    if ($s) { $ramGb = [double]$s.RamGb }
    if ($null -ne $ramGb) {
        if ($ramGb -ge 32) {
            $capScore = $memCapMax
            $capStatus = 'Good'
            $capDetail = ("{0:N1} GB RAM" -f $ramGb)
        } elseif ($ramGb -ge 16) {
            $capScore = $memCapMax * 0.75
            $capStatus = 'Good'
            $capDetail = ("{0:N1} GB RAM (32 GB is more comfortable with Discord/browser)" -f $ramGb)
        } elseif ($ramGb -ge 8) {
            $capScore = $memCapMax * 0.35
            $capStatus = 'Warn'
            $capDetail = ("{0:N1} GB RAM  -  tight for modern games" -f $ramGb)
            $chHint = 'Upgrade RAM toward 16-32 GB'
        } else {
            $capScore = 0
            $capStatus = 'Bad'
            $capDetail = ("{0:N1} GB RAM  -  below modern gaming minimum" -f $ramGb)
        }
    }

    $channels = if ($s) { [string]$s.RamChannels } else { '' }
    $sticks = if ($s) { [int]$s.RamSticks } else { 0 }
    if ($channels -match 'Single') {
        $chScore = 0
        $chStatus = 'Bad'
        $chDetail = "Single-channel RAM ($sticks stick(s))  -  hurts 1% lows"
        $chFix = 'CopyRamTip'
        $chHint = 'Add a matching second stick for dual-channel'
    } elseif ($channels -match '^Dual') {
        $chScore = $memChMax
        $chStatus = 'Good'
        $chDetail = "RAM channels: $channels ($sticks stick(s))"
    } elseif ($channels -match 'Likely') {
        $chScore = $memChMax * 0.85
        $chStatus = 'Good'
        $chDetail = "Likely multi-channel ($sticks sticks)  -  verify in Task Manager"
    } elseif ($sticks -ge 2) {
        $chScore = $memChMax * 0.85
        $chStatus = 'Good'
        $chDetail = "Likely multi-channel ($sticks sticks)  -  verify in Task Manager"
    } elseif ($sticks -eq 1) {
        $chScore = 0
        $chStatus = 'Bad'
        $chDetail = 'One RAM stick  -  almost certainly single-channel'
        $chFix = 'CopyRamTip'
        $chHint = 'Add a matching second stick for dual-channel'
    } else {
        $chScore = 0
        $chStatus = 'Unknown'
        $chDetail = 'Could not determine RAM channel config'
    }

    [void]$checks.Add((New-OptimizationCheck -Id 'memory_capacity' -Category 'Memory' -Status $capStatus `
        -Points $capScore -Max $memCapMax -Title 'RAM capacity' -Detail $capDetail))
    [void]$checks.Add((New-OptimizationCheck -Id 'memory_channels' -Category 'Memory' -Status $chStatus `
        -Points $chScore -Max $memChMax -Title 'RAM channels' -Detail $chDetail `
        -FixHint $chHint -FixAction $chFix))

    # ---- Power (weight 0.20) ----
    $powerMax = 100.0
    $powerScore = 0.0
    $powerStatus = 'Unknown'
    $powerDetail = 'Power plan unknown'
    $powerFix = 'None'
    $powerHint = ''
    $powerName = $null
    try {
        if ($s -and $s.PowerPlan) {
            $powerName = [string]$s.PowerPlan
        } elseif (Get-Command Get-ActivePowerPlanName -EA SilentlyContinue) {
            $powerName = Get-ActivePowerPlanName
        }
    } catch { }
    if ($powerName -and $powerName -ne 'Unknown') {
        if ($powerName -match 'Ultimate|High performance|High Performance') {
            $powerScore = $powerMax
            $powerStatus = 'Good'
            $powerDetail = "Power plan: $powerName"
        } elseif ($powerName -match 'Power saver|Power Saver') {
            $powerScore = 0
            $powerStatus = 'Bad'
            $powerDetail = "Power plan: $powerName  -  CPU may sleep between frames"
            $powerFix = 'GamingOptimize'
            $powerHint = 'Switch to High/Ultimate Performance'
        } elseif ($powerName -match 'Balanced') {
            $powerScore = $powerMax * 0.45
            $powerStatus = 'Warn'
            $powerDetail = "Power plan: $powerName  -  Fine for everyday use; High/Ultimate is steadier for gaming"
            $powerFix = 'GamingOptimize'
            $powerHint = 'Switch to High/Ultimate Performance'
        } else {
            $powerScore = $powerMax * 0.7
            $powerStatus = 'Warn'
            $powerDetail = "Power plan: $powerName"
            $powerFix = 'GamingOptimize'
            $powerHint = 'Prefer High/Ultimate Performance while gaming'
        }
    }
    [void]$checks.Add((New-OptimizationCheck -Id 'power_plan' -Category 'Power' -Status $powerStatus `
        -Points $powerScore -Max $powerMax -Title 'Power plan' -Detail $powerDetail `
        -FixHint $powerHint -FixAction $powerFix))

    # ---- DisplayGpu (weight 0.11) ----
    $refMax = 55.0
    $drvMax = 45.0
    $refScore = 0.0
    $drvScore = 0.0
    $refStatus = 'Unknown'
    $drvStatus = 'Unknown'
    $refDetail = 'Refresh rate unknown'
    $drvDetail = 'GPU driver unknown'
    $refFix = 'None'
    $refHint = ''
    $drvFix = 'None'
    $drvHint = ''

    # Device summary already refreshed the shared GPU list when this score refresh did.
    $primaryGpu = Get-PrimaryVideoController -Refresh:((-not $summaryOk) -and [bool]$Refresh)
    $ref = Get-DisplayRefreshInfo -VideoController $primaryGpu
    if ($null -ne $ref.CurrentHz -and $null -ne $ref.MaxHz) {
        if ($ref.MaxHz -le 60 -or $ref.CurrentHz -ge $ref.MaxHz) {
            $refScore = $refMax
            $refStatus = 'Good'
            $refDetail = ("Display {0} Hz (max {1} Hz)" -f $ref.CurrentHz, $ref.MaxHz)
        } elseif ($ref.MaxHz -ge 120 -and $ref.CurrentHz -le 60) {
            $refScore = 0
            $refStatus = 'Bad'
            $refDetail = ("Display at {0} Hz but panel supports {1} Hz  -  huge wasted headroom" -f $ref.CurrentHz, $ref.MaxHz)
            $refFix = 'OpenDisplay'
            $refHint = 'Set Windows display refresh to the panel maximum'
        } elseif ($ref.CurrentHz -lt ($ref.MaxHz - 5)) {
            $refScore = $refMax * 0.4
            $refStatus = 'Warn'
            $refDetail = ("Display at {0} Hz (max {1} Hz)" -f $ref.CurrentHz, $ref.MaxHz)
            $refFix = 'OpenDisplay'
            $refHint = 'Raise refresh rate in Display settings'
        } else {
            $refScore = $refMax
            $refStatus = 'Good'
            $refDetail = ("Display {0} Hz (max {1} Hz)" -f $ref.CurrentHz, $ref.MaxHz)
        }
    } elseif ($null -ne $ref.CurrentHz) {
        $refScore = $refMax * 0.85
        $refStatus = 'Good'
        $refDetail = ("Display {0} Hz (max unknown)" -f $ref.CurrentHz)
    }

    $drv = Get-GpuDriverInfo -VideoController $primaryGpu
    if ($drv.IsBasic) {
        $drvScore = 0
        $drvStatus = 'Bad'
        $drvDetail = 'Microsoft Basic Display Adapter  -  install GPU vendor drivers'
        $drvHint = 'Install NVIDIA / AMD / Intel graphics drivers'
    } elseif ($drv.VendorOk) {
        if ($null -ne $drv.AgeDays) {
            if ($drv.AgeDays -le 180) {
                $drvScore = $drvMax
                $drvStatus = 'Good'
                $drvDetail = ("{0} driver ({1} days old)" -f $drv.Name, $drv.AgeDays)
            } elseif ($drv.AgeDays -le 365) {
                $drvScore = $drvMax * 0.55
                $drvStatus = 'Warn'
                $drvDetail = ("{0} driver is {1} days old" -f $drv.Name, $drv.AgeDays)
                $drvHint = 'Update GPU drivers from NVIDIA App / AMD Adrenalin / Intel'
            } else {
                $drvScore = $drvMax * 0.25
                $drvStatus = 'Warn'
                $drvDetail = ("{0} driver is {1} days old" -f $drv.Name, $drv.AgeDays)
                $drvHint = 'Update GPU drivers from vendor app'
            }
        } else {
            $drvScore = $drvMax * 0.85
            $drvStatus = 'Good'
            $drvDetail = ("{0} (driver date unknown)" -f $drv.Name)
        }
    } elseif ($drv.Name) {
        $drvScore = $drvMax * 0.7
        $drvStatus = 'Warn'
        $drvDetail = "GPU: $($drv.Name)"
    }

    [void]$checks.Add((New-OptimizationCheck -Id 'display_refresh' -Category 'DisplayGpu' -Status $refStatus `
        -Points $refScore -Max $refMax -Title 'Display refresh rate' -Detail $refDetail `
        -FixHint $refHint -FixAction $refFix))
    [void]$checks.Add((New-OptimizationCheck -Id 'gpu_driver' -Category 'DisplayGpu' -Status $drvStatus `
        -Points $drvScore -Max $drvMax -Title 'GPU driver' -Detail $drvDetail `
        -FixHint $drvHint -FixAction $drvFix))

    # ---- GamingFeatures (weight 0.18) ----
    $gmMax = 45.0
    $dvrMax = 40.0
    $hagsMax = 15.0
    $gmScore = $gmMax
    $dvrScore = $dvrMax
    $hagsScore = $hagsMax  # optional; unknown/off must not soft-cap tuned PCs
    $gmStatus = 'Unknown'
    $dvrStatus = 'Unknown'
    $hagsStatus = 'Unknown'
    $gmDetail = 'Game Mode unknown'
    $dvrDetail = 'Game DVR unknown'
    $hagsDetail = 'HAGS unknown'
    $gmFix = 'None'
    $dvrFix = 'None'

    $gm = $null
    $dvr = $null
    try { if (Get-Command Get-GameModeEnabled -EA SilentlyContinue) { $gm = Get-GameModeEnabled } } catch { }
    try { if (Get-Command Get-GameDvrEnabled -EA SilentlyContinue) { $dvr = Get-GameDvrEnabled } } catch { }

    if ($null -eq $gm) {
        $gmScore = $gmMax
        $gmStatus = 'Unknown'
        $gmDetail = 'Game Mode registry value not set (Windows default is usually On)'
    } elseif ([int]$gm -eq 1) {
        $gmScore = $gmMax
        $gmStatus = 'Good'
        $gmDetail = 'Game Mode: On'
    } else {
        $gmScore = 0
        $gmStatus = 'Bad'
        $gmDetail = 'Game Mode: Off  -  background tasks may interrupt games'
        $gmFix = 'GamingOptimize'
    }

    if ($null -eq $dvr) {
        $dvrScore = $dvrMax
        $dvrStatus = 'Unknown'
        $dvrDetail = 'Xbox Game DVR status unknown'
    } elseif ([int]$dvr -eq 0) {
        $dvrScore = $dvrMax
        $dvrStatus = 'Good'
        $dvrDetail = 'Xbox Game DVR / capture: Off'
    } else {
        $dvrScore = 0
        $dvrStatus = 'Bad'
        $dvrDetail = 'Xbox Game DVR: On  -  can add overlay overhead'
        $dvrFix = 'GamingOptimize'
    }

    $hags = Get-HagsEnabled
    if ($null -eq $hags) {
        $hagsScore = $hagsMax
        $hagsStatus = 'Unknown'
        $hagsDetail = 'Hardware-accelerated GPU scheduling not reported (optional)'
    } elseif ($hags) {
        $hagsScore = $hagsMax
        $hagsStatus = 'Good'
        $hagsDetail = 'HAGS: On'
    } else {
        # Off is a valid choice (driver-dependent). Do not soft-cap a tuned PC at 92.
        $hagsScore = $hagsMax
        $hagsStatus = 'Good'
        $hagsDetail = 'HAGS: Off (optional; enable in Graphics settings if you want to test it)'
    }

    [void]$checks.Add((New-OptimizationCheck -Id 'game_mode' -Category 'GamingFeatures' -Status $gmStatus `
        -Points $gmScore -Max $gmMax -Title 'Game Mode' -Detail $gmDetail `
        -FixHint $(if ($gmFix -eq 'GamingOptimize') { 'Enable Game Mode' } else { '' }) -FixAction $gmFix))
    [void]$checks.Add((New-OptimizationCheck -Id 'game_dvr' -Category 'GamingFeatures' -Status $dvrStatus `
        -Points $dvrScore -Max $dvrMax -Title 'Xbox Game DVR' -Detail $dvrDetail `
        -FixHint $(if ($dvrFix -eq 'GamingOptimize') { 'Turn off Xbox capture / Game DVR' } else { '' }) -FixAction $dvrFix))
    [void]$checks.Add((New-OptimizationCheck -Id 'hags' -Category 'GamingFeatures' -Status $hagsStatus `
        -Points $hagsScore -Max $hagsMax -Title 'HAGS' -Detail $hagsDetail))

    # ---- Background (weight 0.13) ----
    $bgMax = 100.0
    $startupApps = @()
    $startupReadOk = $true
    try { $startupApps = @(Get-StartupApps) } catch {
        $startupReadOk = $false
        $startupApps = @()
    }
    $startupCount = @($startupApps | Where-Object { $_.Enabled }).Count
    $serviceHolds = @()
    if ($startupReadOk) {
        try { $serviceHolds = @(Get-StartupServiceHolds -Apps $startupApps -Refresh:$Refresh) } catch { $serviceHolds = @() }
    }
    $holdText = Format-StartupServiceHoldList $serviceHolds
    $logonText = ''
    if ($startupReadOk) {
        try { $logonText = Format-LogonTaskList (Get-ExtraLogonTaskNames -Apps $startupApps -Refresh:$Refresh) } catch { $logonText = '' }
    }
    $judged = Get-StartupBackgroundJudgement -ReadOk $startupReadOk -EnabledCount $startupCount `
        -AppList (Format-StartupAppList $startupApps) -HoldText $holdText -LogonText $logonText -MaxPoints $bgMax
    $bgScore = $judged.Points
    $bgStatus = $judged.Status
    $bgDetail = $judged.Detail
    $bgFix = $judged.Fix
    $bgHint = $judged.Hint
    [void]$checks.Add((New-OptimizationCheck -Id 'startup_count' -Category 'Background' -Status $bgStatus `
        -Points $bgScore -Max $bgMax -Title 'Startup programs' -Detail $bgDetail `
        -FixHint $bgHint -FixAction $bgFix))

    # ---- Hygiene (weight 0.05) ----
    $hygMax = 100.0
    $hygScore = $hygMax
    $hygStatus = 'Good'
    $hygDetail = 'No restart required'
    $reboot = $false
    $rebootReasons = @()
    try {
        if (Get-Command Get-RebootPendingInfo -EA SilentlyContinue) {
            $ri = Get-RebootPendingInfo -Refresh:$Refresh
            $reboot = [bool]$ri.Pending
            $rebootReasons = @($ri.Reasons)
        } elseif ($s -and $null -ne $s.RebootPending) {
            $reboot = [bool]$s.RebootPending
        } elseif (Get-Command Test-RebootPending -EA SilentlyContinue) {
            $reboot = [bool](Test-RebootPending)
        }
    } catch { }
    if ($reboot) {
        $hygScore = $hygMax * 0.3
        $hygStatus = 'Warn'
        $why = if ($rebootReasons.Count -gt 0) { ($rebootReasons -join ', ') } else { 'Windows reports a pending restart' }
        $hygDetail = ("Restart pending ({0})  -  finish updates/driver installs for a clean session" -f $why)
    }
    [void]$checks.Add((New-OptimizationCheck -Id 'reboot_pending' -Category 'Hygiene' -Status $hygStatus `
        -Points $hygScore -Max $hygMax -Title 'Pending restart' -Detail $hygDetail))

    # ---- Security (weight 0.10) ----
    # Scan age only. Real-time protection, signatures, and Malwarebytes stay on
    # the Security tab. A scan within 20 days keeps full points. Older than that
    # holds the headline score at Needs work.
    $secMax = 100.0
    $secKnown = $false
    $secWhen = $null
    try {
        if (Get-Command Get-SecurityHealth -EA SilentlyContinue) {
            $health = Get-SecurityHealth -Refresh:$Refresh
            if ($health -and $health.Defender -and $health.Defender.ScanTimesKnown) {
                $secKnown = $true
                $secWhen = $health.Defender.LastScanTime
            }
        }
    } catch { }
    $scanFresh = Get-SecurityScanFreshness -LastScan $secWhen -Known $secKnown -MaxAgeDays 20 -MaxPoints $secMax
    $scanFix = 'None'
    if ($scanFresh.Status -eq 'Bad') { $scanFix = 'OpenSecurity' }
    [void]$checks.Add((New-OptimizationCheck -Id 'security_scan' -Category 'Security' -Status $scanFresh.Status `
        -Points $scanFresh.Points -Max $secMax -Title 'Security scan' -Detail $scanFresh.Detail `
        -FixHint $scanFresh.Hint -FixAction $scanFix))

    # ---- Aggregate ----
    # Settings the kit can change (power, game features, startup, reboot, scan)
    # outweigh hardware the PC already has (disk type, RAM). Free space still sits in Storage.
    $weights = @{
        Storage         = 0.14
        Memory          = 0.09
        Power           = 0.20
        DisplayGpu      = 0.11
        GamingFeatures  = 0.18
        Background      = 0.13
        Hygiene         = 0.05
        Security        = 0.10
    }

    $categories = New-Object System.Collections.Generic.List[object]
    $weightedSum = 0.0

    foreach ($catName in @('Storage','Memory','Power','DisplayGpu','GamingFeatures','Background','Hygiene','Security')) {
        $catChecks = @($checks | Where-Object { $_.Category -eq $catName })
        $pts = ($catChecks | Measure-Object -Property Points -Sum).Sum
        $mx = ($catChecks | Measure-Object -Property Max -Sum).Sum
        $pct = if ($mx -gt 0) { ($pts / $mx) * 100.0 } else { 100.0 }
        $w = [double]$weights[$catName]
        $weightedSum += ($pct / 100.0) * $w * 100.0
        [void]$categories.Add([pscustomobject]@{
            Name   = $catName
            Score  = [int][math]::Round($pct)
            Weight = $w
            Points = [math]::Round($pts, 2)
            Max    = [math]::Round($mx, 2)
        })
    }

    $catList = @($categories.ToArray())
    $biggestLimiter = Get-BiggestScoreLimiter $catList
    $weightedOverall = [int][math]::Round($weightedSum)
    $displayed = Get-DisplayedOptimizationScore -WeightedScore $weightedOverall -ScanStatus $scanFresh.Status
    $overall = [int]$displayed.Score
    $grade = Get-OptimizationGrade $overall

    $topFixes = @(
        $checks |
            Where-Object { $_.Status -eq 'Bad' -or $_.Status -eq 'Warn' } |
            Sort-Object @{ Expression = {
                if ($_.Status -eq 'Bad') { 0 } else { 1 }
            } }, @{ Expression = {
                if ($_.Max -gt 0) { ($_.Max - $_.Points) / $_.Max } else { 0 }
            }; Descending = $true } |
            Select-Object -First 3
    )

    # Hardware readiness (not mixed into score)
    $readyBits = New-Object System.Collections.Generic.List[string]
    $readyOk = 0
    $readyTotal = 3
    $hasDgpu = $false
    if ($drv.VendorOk -and -not $drv.IsBasic) { $hasDgpu = $true }
    elseif ($s -and $s.Gpu -and $s.Gpu -notmatch 'Unknown|Basic') { $hasDgpu = $true }
    if ($hasDgpu) { $readyOk++; [void]$readyBits.Add('Discrete/vendor GPU') } else { [void]$readyBits.Add('No clear dGPU') }
    if ($null -ne $ramGb -and $ramGb -ge 16) { $readyOk++; [void]$readyBits.Add('RAM >= 16 GB') } else { [void]$readyBits.Add('RAM < 16 GB') }
    $ssdOk = ($mediaStatus -eq 'Good' -and $mediaType -and $mediaType -notmatch 'HDD')
    if ($ssdOk) { $readyOk++; [void]$readyBits.Add('SSD OS drive') } else { [void]$readyBits.Add('HDD/unknown OS drive') }
    $readyLabel = if ($readyOk -eq 3) { 'Ready' } elseif ($readyOk -ge 2) { 'Mostly ready' } else { 'Limited' }
    $hardwareReadiness = [pscustomobject]@{
        Label   = $readyLabel
        Score   = $readyOk
        OutOf   = $readyTotal
        Summary = ($readyBits -join '; ')
    }

    $result = [pscustomobject]@{
        Score               = [int]$overall
        Grade               = [string]$grade
        BiggestLimiter      = [string]$biggestLimiter
        Categories          = [object[]]$catList
        Checks              = [object[]]@($checks.ToArray())
        TopFixes            = [object[]]@($topFixes)
        HardwareReadiness   = $hardwareReadiness
        WeightedScore       = [int]$displayed.Weighted
        ScoreNote           = [string]$displayed.Note
        Disclaimer          = 'Config/setup score for gaming feel - not a GPU/CPU benchmark.'
    }

    $Script:OptimizationScoreCache = $result
    $Script:OptimizationScoreCacheUtc = [datetime]::UtcNow
    return $result
}

function Format-OptimizationScoreText {
    param(
        [object]$ScoreObject,
        [switch]$Short
    )
    if (-not $ScoreObject) {
        try { $ScoreObject = Get-GamingOptimizationScore } catch { return 'Opt score: unavailable' }
    }
    if ($Short) {
        return ('Opt score: {0}/100 ({1})  -  limiter: {2}' -f $ScoreObject.Score, $ScoreObject.Grade, $ScoreObject.BiggestLimiter)
    }
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add(('Setup score: {0}/100  -  {1}. Hardware you own is part of this. Top fixes are what you can change.' -f $ScoreObject.Score, $ScoreObject.Grade))
    if ($ScoreObject.ScoreNote) { [void]$lines.Add([string]$ScoreObject.ScoreNote) }
    [void]$lines.Add(('Biggest limiter: {0}' -f $ScoreObject.BiggestLimiter))
    [void]$lines.Add(('Hardware readiness: {0} ({1}/{2})  -  {3}' -f `
        $ScoreObject.HardwareReadiness.Label,
        $ScoreObject.HardwareReadiness.Score,
        $ScoreObject.HardwareReadiness.OutOf,
        $ScoreObject.HardwareReadiness.Summary))
    [void]$lines.Add('')
    [void]$lines.Add('Categories:')
    foreach ($c in $ScoreObject.Categories) {
        [void]$lines.Add(('  {0,-16} {1,3}/100  (weight {2:P0})' -f $c.Name, $c.Score, $c.Weight))
    }
    if ($ScoreObject.TopFixes -and $ScoreObject.TopFixes.Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('Top fixes:')
        $i = 1
        foreach ($f in $ScoreObject.TopFixes) {
            $why = if ($f.FixHint) { $f.FixHint } else { $f.Detail }
            [void]$lines.Add(('  {0}. [{1}] {2}  -  {3}' -f $i, $f.Status, $f.Title, $why))
            $i++
        }
    }
    [void]$lines.Add('')
    [void]$lines.Add($ScoreObject.Disclaimer)
    return ($lines -join "`r`n")
}

function Invoke-OptimizationScoreReport {
    Write-Step "Gaming optimization score"
    $score = Get-GamingOptimizationScore -Refresh
    Write-Ok ("Score: {0}/100 ({1})" -f $score.Score, $score.Grade)
    Write-Info ("Biggest limiter: {0}" -f $score.BiggestLimiter)
    Write-Info ("Hardware readiness: {0}  -  {1}" -f $score.HardwareReadiness.Label, $score.HardwareReadiness.Summary)
    foreach ($c in $score.Categories) {
        if ($c.Score -lt 70) {
            Write-Warn ("{0}: {1}/100" -f $c.Name, $c.Score)
        } else {
            Write-Ok ("{0}: {1}/100" -f $c.Name, $c.Score)
        }
    }
    if ($score.TopFixes -and $score.TopFixes.Count -gt 0) {
        Write-Info "Top fixes:"
        foreach ($f in $score.TopFixes) {
            $line = "{0}: {1}" -f $f.Title, $f.Detail
            if ($f.Status -eq 'Bad') { Write-Warn $line } else { Write-Info $line }
        }
    }
    Write-Info $score.Disclaimer
    return $score
}

function Open-TaskScheduler {
    try {
        Start-Process 'taskschd.msc'
        return $true
    } catch {
        return $false
    }
}

function Open-ServicesConsole {
    try {
        Start-Process 'services.msc'
        return $true
    } catch {
        return $false
    }
}

function Open-StartupSettings {
    if (Get-Command Start-UserSettingsPage -EA SilentlyContinue) {
        if (Start-UserSettingsPage 'ms-settings:startupapps') { return $true }
    }
    try {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList 'ms-settings:startupapps'
        return $true
    } catch {
        return $false
    }
}

function Open-DisplaySettings {
    try {
        if (Get-Command Start-UserSettingsPage -EA SilentlyContinue) {
            if (Start-UserSettingsPage 'ms-settings:display') { return $true }
        }
        Start-Process 'ms-settings:display'
        return $true
    } catch {
        try {
            Start-Process 'desk.cpl'
            return $true
        } catch {
            return $false
        }
    }
}

function Invoke-RecommendedOptimizationFixes {
    param(
        [switch]$OpenTips,
        $BeforeScore = $null
    )
    Write-Step "Recommended optimization fixes"
    $before = $BeforeScore
    if (-not $before) {
        $before = Get-GamingOptimizationScore -Refresh
    }

    $needsGaming = $false
    foreach ($f in @($before.Checks)) {
        if ($f.FixAction -eq 'GamingOptimize' -and ($f.Status -eq 'Bad' -or $f.Status -eq 'Warn')) {
            $needsGaming = $true
            break
        }
    }

    if ($needsGaming -and (Get-Command Invoke-GamingOptimize -EA SilentlyContinue)) {
        Invoke-GamingOptimize
        if (Get-Command Clear-HardwareProbeCaches -EA SilentlyContinue) {
            Clear-HardwareProbeCaches
        } else {
            $Script:OptimizationScoreCache = $null
            $Script:PowerPlanCache = $null
        }
    } else {
        Write-Info "No Game Mode / DVR / power-plan auto-fixes needed"
    }

    if ($OpenTips) {
        $opened = @{}
        foreach ($f in @($before.TopFixes)) {
            if (-not $f.FixAction -or $f.FixAction -eq 'None' -or $f.FixAction -eq 'GamingOptimize') { continue }
            if ($opened.ContainsKey($f.FixAction)) { continue }
            $opened[$f.FixAction] = $true
            switch ($f.FixAction) {
                'OpenStorage' {
                    if (Get-Command Open-StorageSettings -EA SilentlyContinue) {
                        [void](Open-StorageSettings)
                        Write-Ok "Opened Storage settings"
                    }
                }
                'CopyRamTip' {
                    if (Get-Command Copy-RamUpgradeTipToClipboard -EA SilentlyContinue) {
                        $tip = Copy-RamUpgradeTipToClipboard
                        Write-Ok "RAM tip copied: $tip"
                    }
                }
                'OpenStartup' {
                    if (Open-StartupSettings) { Write-Ok "Opened Startup apps settings" }
                }
                'OpenServices' {
                    if (Open-ServicesConsole) { Write-Ok "Opened Services" }
                }
                'OpenTasks' {
                    if (Open-TaskScheduler) { Write-Ok "Opened Task Scheduler" }
                }
                'OpenDisplay' {
                    if (Open-DisplaySettings) { Write-Ok "Opened Display settings" }
                }
                'OpenSecurity' {
                    if (Get-Command Open-WindowsSecurity -EA SilentlyContinue) {
                        if (Open-WindowsSecurity) { Write-Ok "Opened Windows Security" }
                    }
                }
            }
        }
    } else {
        foreach ($f in @($before.TopFixes)) {
            if ($f.FixAction -eq 'GamingOptimize' -or $f.FixAction -eq 'None') { continue }
            if ($f.FixHint) { Write-Info ("Manual: {0}" -f $f.FixHint) }
        }
    }

    $Script:OptimizationScoreCache = $null
    $after = Get-GamingOptimizationScore -Refresh
    Write-Ok ("Score after fixes: {0}/100 ({1})  -  was {2}" -f $after.Score, $after.Grade, $before.Score)
    return $after
}
