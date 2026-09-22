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
        [ValidateSet('GamingOptimize','OpenStorage','CopyRamTip','OpenStartup','OpenDisplay','None')]$FixAction = 'None'
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

function Get-PrimaryVideoController {
    param([switch]$Refresh)
    if (-not $Refresh -and $null -ne $Script:PrimaryVideoCache -and (([datetime]::UtcNow - $Script:PrimaryVideoCacheUtc).TotalSeconds -lt 30)) {
        return $Script:PrimaryVideoCache
    }
    $vc = $null
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -EA SilentlyContinue |
            Where-Object { $_.Name -and $_.Name -notmatch 'Basic|Remote|Microsoft Basic' } |
            Sort-Object { if ($_.AdapterRAM -gt 0) { -$_.AdapterRAM } else { 0 } })
        if ($gpus.Count) { $vc = $gpus[0] }
        else { $vc = Get-CimInstance Win32_VideoController -EA SilentlyContinue | Select-Object -First 1 }
    } catch {
        $vc = $null
    }
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

function Get-StartupEntryCount {
    $count = 0
    $paths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($p in $paths) {
        try {
            if (Test-Path $p) {
                $props = Get-ItemProperty $p -EA SilentlyContinue
                if ($props) {
                    $names = $props.PSObject.Properties.Name | Where-Object {
                        $_ -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')
                    }
                    $count += @($names).Count
                }
            }
        } catch { }
    }
    return $count
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

function Get-SystemDriveCapacityGB {
    try {
        $vol = Get-Volume -DriveLetter C -EA SilentlyContinue
        if ($vol -and $vol.Size -gt 0) {
            return [math]::Round($vol.Size / 1GB, 1)
        }
    } catch { }
    try {
        $logical = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA SilentlyContinue
        if ($logical -and $logical.Size -gt 0) {
            return [math]::Round($logical.Size / 1GB, 1)
        }
    } catch { }
    return $null
}

function Get-OptimizationGrade([int]$Score) {
    if ($Score -ge 85) { return 'Excellent' }
    if ($Score -ge 70) { return 'Good' }
    if ($Score -ge 50) { return 'Needs work' }
    return 'Critical'
}

function Get-GamingOptimizationScore {
    param([switch]$Refresh)

    if (-not $Refresh -and $Script:OptimizationScoreCache -and (([datetime]::UtcNow - $Script:OptimizationScoreCacheUtc).TotalSeconds -lt 30)) {
        return $Script:OptimizationScoreCache
    }

    $checks = New-Object System.Collections.Generic.List[object]
    $s = $null
    try { $s = Get-DeviceSummary -Refresh:$Refresh } catch { }

    # ---- Storage (weight 0.22) ----
    $mediaPts = 40.0
    $freePts = 40.0
    $healthPts = 20.0
    $mediaScore = $mediaPts
    $freeScore = $freePts
    $healthScore = $healthPts
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
    } catch { }

    $mediaType = $null
    if ($disk) {
        $mediaType = [string]$disk.MediaType
        $healthStr = [string]$disk.HealthStatus
        if ($mediaType -match 'SSD|Unspecified') {
            $mediaScore = $mediaPts
            $mediaStatus = 'Good'
            $mediaDetail = "System disk: $($disk.FriendlyName) ($mediaType)"
        } elseif ($mediaType -match 'HDD') {
            $mediaScore = 0
            $mediaStatus = 'Bad'
            $mediaDetail = "System disk is HDD ($($disk.FriendlyName))  -  slow loads and stutter risk"
            $mediaHint = 'Move Windows/games to an SSD when you can'
        } else {
            $mediaScore = $mediaPts * 0.6
            $mediaStatus = 'Warn'
            $mediaDetail = "System disk media: $mediaType"
        }

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
            $healthScore = $healthPts
            $healthStatus = 'Unknown'
            $healthDetail = "Disk health: $healthStr"
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

    # ---- Memory (weight 0.20) ----
    $memCapMax = 50.0
    $memChMax = 50.0
    $capScore = $memCapMax
    $chScore = $memChMax
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
        $chScore = $memChMax
        $chStatus = 'Unknown'
        $chDetail = 'Could not determine RAM channel config'
    }

    [void]$checks.Add((New-OptimizationCheck -Id 'memory_capacity' -Category 'Memory' -Status $capStatus `
        -Points $capScore -Max $memCapMax -Title 'RAM capacity' -Detail $capDetail))
    [void]$checks.Add((New-OptimizationCheck -Id 'memory_channels' -Category 'Memory' -Status $chStatus `
        -Points $chScore -Max $memChMax -Title 'RAM channels' -Detail $chDetail `
        -FixHint $chHint -FixAction $chFix))

    # ---- Power (weight 0.18) ----
    $powerMax = 100.0
    $powerScore = $powerMax
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
    if ($powerName) {
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

    # ---- DisplayGpu (weight 0.15) ----
    $refMax = 55.0
    $drvMax = 45.0
    $refScore = $refMax
    $drvScore = $drvMax
    $refStatus = 'Unknown'
    $drvStatus = 'Unknown'
    $refDetail = 'Refresh rate unknown'
    $drvDetail = 'GPU driver unknown'
    $refFix = 'None'
    $refHint = ''
    $drvFix = 'None'
    $drvHint = ''

    $primaryGpu = Get-PrimaryVideoController -Refresh:$Refresh
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

    # ---- GamingFeatures (weight 0.12) ----
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

    # ---- Background (weight 0.08) ----
    $bgMax = 100.0
    $startupCount = Get-StartupEntryCount
    $bgScore = $bgMax
    $bgStatus = 'Good'
    $bgDetail = "Startup Run entries: $startupCount"
    $bgFix = 'None'
    $bgHint = ''
    if ($startupCount -le 5) {
        $bgScore = $bgMax
        $bgStatus = 'Good'
    } elseif ($startupCount -le 12) {
        $bgScore = $bgMax * 0.55
        $bgStatus = 'Warn'
        $bgDetail = "Startup Run entries: $startupCount  -  trim unused launchers"
        $bgFix = 'OpenStartup'
        $bgHint = 'Disable unused startup apps'
    } else {
        $bgScore = $bgMax * 0.2
        $bgStatus = 'Bad'
        $bgDetail = "Startup Run entries: $startupCount  -  heavy background load"
        $bgFix = 'OpenStartup'
        $bgHint = 'Disable unused startup apps'
    }
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

    # ---- Aggregate ----
    $weights = @{
        Storage         = 0.22
        Memory          = 0.20
        Power           = 0.18
        DisplayGpu      = 0.15
        GamingFeatures  = 0.12
        Background      = 0.08
        Hygiene         = 0.05
    }

    $categories = New-Object System.Collections.Generic.List[object]
    $weightedSum = 0.0
    $lowestCatScore = 101.0
    $biggestLimiter = 'None'

    foreach ($catName in @('Storage','Memory','Power','DisplayGpu','GamingFeatures','Background','Hygiene')) {
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
        if ($pct -lt $lowestCatScore) {
            $lowestCatScore = $pct
            $biggestLimiter = $catName
        }
    }

    $overall = [int][math]::Round($weightedSum)
    if ($overall -lt 0) { $overall = 0 }
    if ($overall -gt 100) { $overall = 100 }
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
        Categories          = [object[]]@($categories.ToArray())
        Checks              = [object[]]@($checks.ToArray())
        TopFixes            = [object[]]@($topFixes)
        HardwareReadiness   = $hardwareReadiness
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
    [void]$lines.Add(('Gaming optimization: {0}/100  -  {1}' -f $ScoreObject.Score, $ScoreObject.Grade))
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

function Open-StartupSettings {
    try {
        Start-Process 'ms-settings:startupapps'
        return $true
    } catch {
        try {
            Start-Process 'shell:startup'
            return $true
        } catch {
            return $false
        }
    }
}

function Open-DisplaySettings {
    try {
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
                'OpenDisplay' {
                    if (Open-DisplaySettings) { Write-Ok "Opened Display settings" }
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
