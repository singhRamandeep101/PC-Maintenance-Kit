#Requires -Version 5.1
$Script:SecurityHealthCache = $null
$Script:SecurityHealthCacheUtc = [datetime]::MinValue

function Get-SecurityNoteProperty($Object, [string]$Name) {
    if (-not $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Format-SecurityWhen($Value) {
    if ($null -eq $Value) { return 'Never' }
    $dt = $null
    if ($Value -is [datetime]) {
        $dt = $Value
    } else {
        try { $dt = [datetime]$Value } catch { return 'Unknown' }
    }
    if ($dt.Year -lt 2000) { return 'Never' }
    return $dt.ToString('yyyy-MM-dd HH:mm')
}

function ConvertTo-SecurityDate($Value) {
    if ($null -eq $Value) { return $null }
    $dt = $null
    if ($Value -is [datetime]) {
        $dt = $Value
    } else {
        try { $dt = [datetime]$Value } catch { return $null }
    }
    if ($dt.Year -lt 2000) { return $null }
    return $dt
}

function Get-NewerSecurityDate($Left, $Right) {
    $a = ConvertTo-SecurityDate $Left
    $b = ConvertTo-SecurityDate $Right
    if ($a -and $b) {
        if ($a -ge $b) { return $a }
        return $b
    }
    if ($a) { return $a }
    return $b
}

function Get-SecuritySignatureAgeDays($Value) {
    if ($null -eq $Value) { return $null }
    $dt = $null
    if ($Value -is [datetime]) {
        $dt = $Value
    } else {
        try { $dt = [datetime]$Value } catch { return $null }
    }
    if ($dt.Year -lt 2000) { return $null }
    $days = [int]([datetime]::Now - $dt).TotalDays
    if ($days -lt 0) { return 0 }
    return $days
}

function Get-MalwarebytesFileVersion([string]$Path) {
    if (-not $Path) { return $null }
    try {
        $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        $version = [string]$info.FileVersion
        if (-not $version) { $version = [string]$info.ProductVersion }
        if ($version) { return $version.Trim() }
    } catch { }
    return $null
}

function Find-MalwarebytesExeUnder([string]$Root) {
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
    $preferred = $null
    $fallback = $null
    try {
        $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -EA SilentlyContinue | Where-Object {
            $_.Name -eq 'Malwarebytes.exe' -or $_.Name -eq 'MBAM.exe'
        })
    } catch {
        return $null
    }
    foreach ($file in $files) {
        if ($file.Name -eq 'Malwarebytes.exe') { $preferred = $file.FullName; break }
        if (-not $fallback) { $fallback = $file.FullName }
    }
    if ($preferred) { return $preferred }
    return $fallback
}

function Find-MalwarebytesFromUninstallKey {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        $entries = @()
        try { $entries = @(Get-ItemProperty -Path $key -EA SilentlyContinue) } catch { $entries = @() }
        foreach ($entry in $entries) {
            $name = [string]$entry.DisplayName
            if ($name -notmatch 'Malwarebytes') { continue }
            $candidates = @()
            if ($entry.DisplayIcon) { $candidates += ([string]$entry.DisplayIcon -replace ',.*$','').Trim('"') }
            if ($entry.InstallLocation) {
                $dir = [string]$entry.InstallLocation
                $candidates += (Join-Path $dir 'Malwarebytes.exe')
                $candidates += (Join-Path $dir 'MBAM.exe')
                $candidates += (Join-Path $dir 'Anti-Malware\Malwarebytes.exe')
                $candidates += (Join-Path $dir 'Anti-Malware\MBAM.exe')
            }
            foreach ($candidate in $candidates) {
                if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                    $leaf = [System.IO.Path]::GetFileName($candidate)
                    if ($leaf -eq 'Malwarebytes.exe' -or $leaf -eq 'MBAM.exe') { return $candidate }
                }
            }
        }
    }
    return $null
}

function Find-MalwarebytesInstall {
    param([string[]]$SearchRoots)

    $found = [pscustomobject]@{
        Installed = $false
        Path      = $null
        Version   = $null
        Source    = $null
    }

    # A caller-supplied root is the whole search. Tests use this so a fake
    # tree cannot fall through to a real install on the machine.
    if ($PSBoundParameters.ContainsKey('SearchRoots')) {
        foreach ($root in @($SearchRoots)) {
            $exe = Find-MalwarebytesExeUnder $root
            if ($exe) {
                $found.Installed = $true
                $found.Path = $exe
                $found.Version = Get-MalwarebytesFileVersion $exe
                $found.Source = 'SearchRoot'
                break
            }
        }
        return $found
    }

    $exe = $null
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        foreach ($leaf in @('Malwarebytes\Anti-Malware\Malwarebytes.exe', 'Malwarebytes\Anti-Malware\MBAM.exe')) {
            $candidate = Join-Path $base $leaf
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $exe = $candidate
                break
            }
        }
        if ($exe) { break }
    }
    if (-not $exe) {
        try { $exe = Find-MalwarebytesFromUninstallKey } catch { $exe = $null }
    }

    $service = $null
    try { $service = Get-Service -Name 'MBAMService' -EA SilentlyContinue } catch { $service = $null }

    if ($exe) {
        $found.Installed = $true
        $found.Path = $exe
        $found.Version = Get-MalwarebytesFileVersion $exe
        $found.Source = 'Path'
    } elseif ($service) {
        $found.Installed = $true
        $found.Source = 'Service'
    }
    return $found
}

function Get-DefenderHealthProbe {
    $probe = [pscustomobject]@{
        RealTime          = 'Unknown'
        Signatures        = 'Unknown'
        SignatureAgeDays  = $null
        LastQuickScan     = 'Unknown'
        LastFullScan      = 'Unknown'
        ScanTimesKnown    = $false
        LastScanTime      = $null
        ThreatCount       = $null
        Threats           = 'Unknown'
    }
    if (-not (Get-Command Get-MpComputerStatus -EA SilentlyContinue)) { return $probe }
    $status = $null
    try { $status = Get-MpComputerStatus -EA Stop } catch { return $probe }
    if (-not $status) { return $probe }

    $rtp = Get-SecurityNoteProperty $status 'RealTimeProtectionEnabled'
    if ($rtp -eq $true) { $probe.RealTime = 'On' }
    elseif ($rtp -eq $false) { $probe.RealTime = 'Off' }

    $updated = Get-SecurityNoteProperty $status 'AntivirusSignatureLastUpdated'
    $age = Get-SecuritySignatureAgeDays $updated
    $probe.SignatureAgeDays = $age
    $outOfDate = Get-SecurityNoteProperty $status 'DefenderSignaturesOutOfDate'
    $stale = $false
    if ($outOfDate -eq $true) { $stale = $true }
    if ($null -ne $age -and $age -gt 7) { $stale = $true }
    if ($null -ne $updated) {
        $updatedDt = $null
        if ($updated -is [datetime]) { $updatedDt = $updated }
        else { try { $updatedDt = [datetime]$updated } catch { $updatedDt = $null } }
        if ($updatedDt -and $updatedDt.Year -lt 2000) { $stale = $true }
    }
    if ($stale) { $probe.Signatures = 'Out of date' }
    elseif ($null -ne $age -or $outOfDate -eq $false) { $probe.Signatures = 'Current' }

    $quickScan = Get-SecurityNoteProperty $status 'QuickScanEndTime'
    $fullScan = Get-SecurityNoteProperty $status 'FullScanEndTime'
    $probe.LastQuickScan = Format-SecurityWhen $quickScan
    $probe.LastFullScan = Format-SecurityWhen $fullScan
    $probe.ScanTimesKnown = $true
    $probe.LastScanTime = Get-NewerSecurityDate $quickScan $fullScan

    if (Get-Command Get-MpThreat -EA SilentlyContinue) {
        try {
            $threats = @(Get-MpThreat -EA Stop)
            $active = 0
            foreach ($threat in $threats) {
                $isActive = Get-SecurityNoteProperty $threat 'IsActive'
                if ($null -ne $isActive) {
                    if (Test-DefenderThreatActive $isActive) { $active++ }
                    continue
                }
                $statusId = Get-SecurityNoteProperty $threat 'ThreatStatusID'
                if ($statusId -eq 1 -or $statusId -eq 102) { $active++ }
            }
            $probe.ThreatCount = $active
            if ($active -gt 0) { $probe.Threats = ("{0} active" -f $active) } else { $probe.Threats = 'None' }
        } catch { }
    }
    return $probe
}

function Test-FirewallProfileOn($Profile) {
    $raw = Get-SecurityNoteProperty $Profile 'Enabled'
    if ($null -eq $raw) { return $null }
    $text = [string]$raw
    if ($text -eq 'True' -or $text -eq '1') { return $true }
    if ($text -eq 'False' -or $text -eq '0') { return $false }
    return $null
}

function Get-FirewallHealthProbe {
    $probe = [pscustomobject]@{
        Status = 'Unknown'
        Detail = 'Unknown'
    }
    if (-not (Get-Command Get-NetFirewallProfile -EA SilentlyContinue)) { return $probe }
    $profiles = @()
    try { $profiles = @(Get-NetFirewallProfile -EA Stop) } catch { return $probe }
    if ($profiles.Count -eq 0) { return $probe }

    $anyOn = $false
    $offNames = New-Object System.Collections.Generic.List[string]
    foreach ($profile in $profiles) {
        $flag = Test-FirewallProfileOn $profile
        if ($flag -eq $true) { $anyOn = $true }
        elseif ($flag -eq $false) {
            $name = [string](Get-SecurityNoteProperty $profile 'Name')
            if (-not $name) { $name = 'Profile' }
            [void]$offNames.Add($name)
        }
    }
    if ($offNames.Count -gt 0) {
        $probe.Status = 'Off'
        $probe.Detail = ("Off: {0}" -f ($offNames -join ', '))
    } elseif ($anyOn) {
        $probe.Status = 'On'
        $probe.Detail = 'All profiles on'
    }
    return $probe
}

function Format-MalwarebytesDetail($Install) {
    if (-not $Install -or -not $Install.Installed) { return 'Not installed' }
    if ($Install.Version) { return ("Installed ({0})" -f $Install.Version) }
    return 'Installed'
}

function Test-DefenderThreatActive($Value) {
    # [bool]'False' is true in PowerShell, because any non-empty string converts
    # to true. Defender's IsActive has to be read as a real yes/no.
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [byte] -or $Value -is [int] -or $Value -is [long]) { return ([int64]$Value) -ne 0 }
    $text = [string]$Value
    if ($text -eq 'True' -or $text -eq '1') { return $true }
    return $false
}

function Format-SignatureHealthText($Defender) {
    if (-not $Defender -or $Defender.Signatures -eq 'Unknown') { return 'Unknown' }
    if ($null -ne $Defender.SignatureAgeDays) {
        if ([int]$Defender.SignatureAgeDays -le 0) { return ("{0} (today)" -f $Defender.Signatures) }
        $unit = 'days'
        if ([int]$Defender.SignatureAgeDays -eq 1) { $unit = 'day' }
        return ("{0} ({1} {2})" -f $Defender.Signatures, [int]$Defender.SignatureAgeDays, $unit)
    }
    return [string]$Defender.Signatures
}

function Get-SecurityHealth {
    param([switch]$Refresh)
    # Long enough to share one probe across the score and the Security tab.
    if (-not $Refresh -and $Script:SecurityHealthCache -and (([datetime]::UtcNow - $Script:SecurityHealthCacheUtc).TotalSeconds -lt 10)) {
        return $Script:SecurityHealthCache
    }
    if (Get-Command Pump-Ui -EA SilentlyContinue) { Pump-Ui }

    $defender = Get-DefenderHealthProbe
    if (Get-Command Pump-Ui -EA SilentlyContinue) { Pump-Ui }
    $firewall = Get-FirewallHealthProbe
    $mb = Find-MalwarebytesInstall

    $reasons = New-Object System.Collections.Generic.List[string]
    if ($defender.RealTime -eq 'Off') {
        [void]$reasons.Add('Real-time protection is off')
    } elseif ($defender.RealTime -eq 'Unknown') {
        [void]$reasons.Add('Windows Defender status could not be read')
    }
    if ($defender.Signatures -eq 'Out of date') {
        [void]$reasons.Add('Defender signatures are out of date')
    }
    if ($firewall.Status -eq 'Off') {
        [void]$reasons.Add(("Firewall {0}" -f $firewall.Detail))
    }
    if ($null -ne $defender.ThreatCount -and $defender.ThreatCount -gt 0) {
        [void]$reasons.Add(("{0} active threat(s)" -f $defender.ThreatCount))
    }

    $verdict = 'Protected'
    if ($reasons.Count -gt 0) { $verdict = 'Needs attention' }

    $health = [pscustomobject]@{
        Verdict      = $verdict
        Reasons      = @($reasons.ToArray())
        Defender     = $defender
        Firewall     = $firewall
        Malwarebytes = [pscustomobject]@{
            Installed = [bool]$mb.Installed
            Path      = $mb.Path
            Version   = $mb.Version
            Detail    = (Format-MalwarebytesDetail $mb)
        }
    }
    $Script:SecurityHealthCache = $health
    $Script:SecurityHealthCacheUtc = [datetime]::UtcNow
    return $health
}

function Format-SecurityHealthText {
    $health = Get-SecurityHealth
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add(("Security: {0}" -f $health.Verdict))
    if ($health.Reasons -and @($health.Reasons).Count -gt 0) {
        foreach ($reason in @($health.Reasons)) {
            [void]$lines.Add(("  - {0}" -f $reason))
        }
    }
    [void]$lines.Add(("  Defender real-time: {0}" -f $health.Defender.RealTime))
    [void]$lines.Add(("  Signatures:         {0}" -f (Format-SignatureHealthText $health.Defender)))
    [void]$lines.Add(("  Last quick scan:    {0}" -f $health.Defender.LastQuickScan))
    [void]$lines.Add(("  Last full scan:     {0}" -f $health.Defender.LastFullScan))
    [void]$lines.Add(("  Threats:            {0}" -f $health.Defender.Threats))
    [void]$lines.Add(("  Firewall:           {0}" -f $health.Firewall.Detail))
    [void]$lines.Add(("  Malwarebytes:       {0}" -f $health.Malwarebytes.Detail))
    [void]$lines.Add('')
    [void]$lines.Add('Scans run in Windows Security or Malwarebytes, not in this kit.')
    return ($lines -join "`r`n")
}

function Open-WindowsSecurity {
    try {
        Start-Process "windowsdefender:"
        return $true
    } catch {
        return $false
    }
}

function Open-Malwarebytes {
    $install = Find-MalwarebytesInstall
    if (-not $install.Installed -or -not $install.Path) { return $false }
    if (-not (Test-Path -LiteralPath $install.Path -PathType Leaf)) { return $false }
    try {
        Start-Process -FilePath $install.Path
        return $true
    } catch {
        return $false
    }
}
