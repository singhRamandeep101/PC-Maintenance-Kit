#Requires -Version 5.1
$Script:DeviceSummaryCache = $null
$Script:DeviceSummaryCacheUtc = [datetime]::MinValue

function Get-RamUpgradeTip {
    $s = Get-DeviceSummary
    $part = [string]$s.RamPartNumber
    if ($s.RamChannels -match 'Single' -or $s.RamSticks -eq 1) {
        if ($part -and $part.Length -gt 2) {
            return "You have 1 stick ($part). Buy a matching second stick of the same model for dual-channel. Search: $part"
        }
        return "You have single-channel RAM. Add a matching second stick (same size/speed) for dual-channel - big gaming 1% lows win."
    }
    return "RAM looks multi-stick. Confirm dual-channel in Task Manager > Performance > Memory."
}

function Copy-RamUpgradeTipToClipboard {
    $tip = Get-RamUpgradeTip
    Set-Clipboard -Value $tip
    return $tip
}

function Invoke-RestartComputerConfirmed {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Restart this PC now?`nSave your game / work first.",
        "Confirm restart",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
    Restart-Computer -Force
    return $true
}

function Start-UserSettingsPage([string]$Uri) {
    # This kit runs as Administrator. Settings then opens on its home page
    # and drops the section. explorer.exe belongs to the normal user session,
    # so the page in the address actually opens.
    $explorer = Join-Path $env:SystemRoot 'explorer.exe'
    try {
        Start-Process -FilePath $explorer -ArgumentList $Uri
        return $true
    } catch {
        try {
            Start-Process $Uri
            return $true
        } catch {
            return $false
        }
    }
}

function Open-StorageSettings {
    try {
        if (Start-UserSettingsPage 'ms-settings:storagesense') { return $true }
        Start-Process "ms-settings:storagesense"
        return $true
    } catch {
        try {
            Start-Process explorer.exe "shell:::{F96C3FC1-EB3B-4AFC-BB16-AA89C46AD1C7}"
            return $true
        } catch {
            return $false
        }
    }
}

function Get-DeviceSummary {
    param([switch]$Refresh)
    if (-not $Refresh -and $Script:DeviceSummaryCache -and (([datetime]::UtcNow - $Script:DeviceSummaryCacheUtc).TotalSeconds -lt 600)) {
        return $Script:DeviceSummaryCache
    }

    if (Get-Command Pump-Ui -EA SilentlyContinue) { Pump-Ui }

    $cpu = (Get-CimInstance Win32_Processor -EA SilentlyContinue | Select-Object -First 1).Name
    if (-not $cpu) { $cpu = "Unknown CPU" }
    if (Get-Command Pump-Ui -EA SilentlyContinue) { Pump-Ui }

    $gpu = "Unknown GPU"
    if (Get-Command Get-VideoControllers -EA SilentlyContinue) {
        $gpus = @(Get-VideoControllers -Refresh:$Refresh | ForEach-Object { [string]$_.Name } | Where-Object { $_ } | Select-Object -Unique)
        if ($gpus.Count) { $gpu = $gpus -join " | " }
    } else {
        $gpus = @(Get-CimInstance Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -and $_.Name -notmatch 'Basic|Remote|Microsoft Basic' } | Select-Object -ExpandProperty Name -Unique)
        if ($gpus.Count) { $gpu = $gpus -join " | " }
    }
    if (Get-Command Pump-Ui -EA SilentlyContinue) { Pump-Ui }

    $sticks = @(Get-CimInstance Win32_PhysicalMemory -EA SilentlyContinue)
    $ramGb = [math]::Round((($sticks | Measure-Object Capacity -Sum).Sum) / 1GB, 1)
    $ramSlots = $sticks.Count
    $ramPart = if ($sticks.Count -and $sticks[0].PartNumber) { $sticks[0].PartNumber.Trim() } else { "" }
    $ramChannels = "Unknown"
    try {
        $channels = @($sticks | ForEach-Object { $_.BankLabel } | Where-Object { $_ } | ForEach-Object {
            if ($_ -match 'CHANNEL\s*([A-Z])') { $Matches[1] } else { $_ }
        } | Select-Object -Unique)
        if ($channels.Count -ge 2) { $ramChannels = "Dual (or more)" }
        elseif ($ramSlots -eq 1) { $ramChannels = "Single-channel (add matching stick)" }
        elseif ($ramSlots -ge 2) { $ramChannels = "Likely dual (verify in Task Manager)" }
    } catch { }

    if (Get-Command Pump-Ui -EA SilentlyContinue) { Pump-Ui }

    $diskName = "Unknown"
    $diskHealth = "Unknown"
    $media = $null
    try {
        if (Get-Command Get-SystemDisk -EA SilentlyContinue) {
            $media = Get-SystemDisk -Refresh:$Refresh
        }
        if ($media) {
            $diskName = $media.FriendlyName
            $diskHealth = [string]$media.HealthStatus
        }
    } catch {
        Write-Warn ("Could not read the system disk: {0}" -f $_.Exception.Message)
    }

    $free = Get-CFreeGB -Refresh:$Refresh
    $trim = "Unknown"
    try {
        # Free space just read C:. Reuse that object for the file system.
        $logical = Get-SystemLogicalDisk
        if ($logical -and [string]$logical.FileSystem -eq 'NTFS') {
            if ($media -and $media.MediaType -match 'SSD|Unspecified') {
                $trim = "SSD detected (TRIM supported on modern Windows)"
            } elseif ($media -and $media.MediaType -match 'HDD') {
                $trim = "HDD (TRIM not applicable)"
            } else {
                $trim = "NTFS volume (TRIM available if drive is SSD)"
            }
        }
    } catch { }

    $power = Get-ActivePowerPlanName -Refresh:$Refresh
    $reboot = Test-RebootPending -Refresh:$Refresh

    $summary = [pscustomobject]@{
        Cpu           = $cpu.Trim()
        Gpu           = $gpu
        RamGb         = $ramGb
        RamSticks     = $ramSlots
        RamPartNumber = $ramPart
        RamChannels   = $ramChannels
        DiskName      = $diskName
        DiskHealth    = $diskHealth
        DiskMediaType = if ($media) { [string]$media.MediaType } else { $null }
        TrimInfo      = $trim
        FreeGb        = $free
        PowerPlan     = $power
        RebootPending = $reboot
    }
    $Script:DeviceSummaryCache = $summary
    $Script:DeviceSummaryCacheUtc = [datetime]::UtcNow
    return $summary
}

function Format-DeviceSummaryText {
    $s = Get-DeviceSummary
    $rebootLine = if ($s.RebootPending) { "YES - restart recommended" } else { "No" }
    $ramPartLine = if ($s.RamPartNumber) { "RAM part:   $($s.RamPartNumber)" } else { $null }
    $optLine = $null
    try {
        if (Get-Command Format-OptimizationScoreText -EA SilentlyContinue) {
            $optLine = Format-OptimizationScoreText -Short
        }
    } catch { }
    $lines = @()
    if ($optLine) { $lines += $optLine; $lines += "" }
    $lines += @(
        "CPU:        $($s.Cpu)"
        "GPU:        $($s.Gpu)"
        "RAM:        $($s.RamGb) GB ($($s.RamSticks) stick(s)) - $($s.RamChannels)"
    )
    if ($ramPartLine) { $lines += $ramPartLine }
    $lines += @(
        "Disk:       $($s.DiskName) [$($s.DiskHealth)]"
        "TRIM:       $($s.TrimInfo)"
        "C: free:    $($s.FreeGb) GB"
        "Power:      $($s.PowerPlan)"
        "Reboot:     $rebootLine"
        ""
        "Tip: $(Get-RamUpgradeTip)"
    )
    return ($lines -join "`r`n")
}

function Invoke-DeviceHealthReport {
    Write-Step "Device health"
    $s = Get-DeviceSummary
    Write-Ok ("CPU: {0}" -f $s.Cpu)
    Write-Ok ("GPU: {0}" -f $s.Gpu)
    if ($s.RamChannels -match 'Single') {
        Write-Warn ("RAM: {0} GB / {1} stick(s) - {2}" -f $s.RamGb, $s.RamSticks, $s.RamChannels)
        if ($s.RamPartNumber) { Write-Info ("Part number: {0}" -f $s.RamPartNumber) }
    } else {
        Write-Ok ("RAM: {0} GB / {1} stick(s) - {2}" -f $s.RamGb, $s.RamSticks, $s.RamChannels)
    }
    Write-Ok ("Disk (C:): {0} - {1}" -f $s.DiskName, $s.DiskHealth)
    Write-Ok ("C: free: {0} GB" -f $s.FreeGb)
    Write-Ok ("Power plan: {0}" -f $s.PowerPlan)
    if ($s.RebootPending) {
        Write-Warn "Restart pending"
    } else {
        Write-Ok "No pending restart"
    }
}
