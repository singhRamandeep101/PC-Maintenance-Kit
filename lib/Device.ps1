function Get-DeviceSummary {
    $cpu = (Get-CimInstance Win32_Processor -EA SilentlyContinue | Select-Object -First 1).Name
    if (-not $cpu) { $cpu = "Unknown CPU" }

    $gpus = @(Get-CimInstance Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -and $_.Name -notmatch 'Basic|Remote|Microsoft' } | Select-Object -ExpandProperty Name -Unique)
    $gpu = if ($gpus.Count) { $gpus -join " | " } else { "Unknown GPU" }

    $sticks = @(Get-CimInstance Win32_PhysicalMemory -EA SilentlyContinue)
    $ramGb = [math]::Round((($sticks | Measure-Object Capacity -Sum).Sum) / 1GB, 1)
    $ramSlots = $sticks.Count
    $ramChannels = "Unknown"
    try {
        $channels = @($sticks | ForEach-Object { $_.BankLabel } | Where-Object { $_ } | ForEach-Object {
            if ($_ -match 'CHANNEL\s*([A-Z])') { $Matches[1] } else { $_ }
        } | Select-Object -Unique)
        if ($channels.Count -ge 2) { $ramChannels = "Dual (or more)" }
        elseif ($ramSlots -eq 1) { $ramChannels = "Single-channel (add matching stick)" }
        elseif ($ramSlots -ge 2) { $ramChannels = "Likely dual (verify in Task Manager)" }
    } catch { }

    $diskName = "Unknown"
    $diskHealth = "Unknown"
    try {
        $d = Get-PhysicalDisk | Select-Object -First 1
        $diskName = $d.FriendlyName
        $diskHealth = [string]$d.HealthStatus
    } catch { }

    $trim = "Unknown"
    try {
        $vol = Get-Volume -DriveLetter C -EA SilentlyContinue
        if ($vol) {
            $trim = "Available (SSD TRIM supported on modern Windows)"
        }
    } catch { }

    $free = Get-CFreeGB
    $power = Get-ActivePowerPlanName
    $reboot = Test-RebootPending

    return [pscustomobject]@{
        Cpu          = $cpu.Trim()
        Gpu          = $gpu
        RamGb        = $ramGb
        RamSticks    = $ramSlots
        RamChannels  = $ramChannels
        DiskName     = $diskName
        DiskHealth   = $diskHealth
        TrimInfo     = $trim
        FreeGb       = $free
        PowerPlan    = $power
        RebootPending = $reboot
    }
}

function Format-DeviceSummaryText {
    $s = Get-DeviceSummary
    $rebootLine = if ($s.RebootPending) { "YES - restart recommended" } else { "No" }
    @(
        "CPU:        $($s.Cpu)"
        "GPU:        $($s.Gpu)"
        "RAM:        $($s.RamGb) GB ($($s.RamSticks) stick(s)) - $($s.RamChannels)"
        "Disk:       $($s.DiskName) [$($s.DiskHealth)]"
        "TRIM:       $($s.TrimInfo)"
        "C: free:    $($s.FreeGb) GB"
        "Power:      $($s.PowerPlan)"
        "Reboot:     $rebootLine"
    ) -join "`r`n"
}

function Invoke-DeviceHealthReport {
    Write-Step "Device health"
    $s = Get-DeviceSummary
    Write-Ok ("CPU: {0}" -f $s.Cpu)
    Write-Ok ("GPU: {0}" -f $s.Gpu)
    if ($s.RamChannels -match 'Single') {
        Write-Warn ("RAM: {0} GB / {1} stick(s) - {2}" -f $s.RamGb, $s.RamSticks, $s.RamChannels)
    } else {
        Write-Ok ("RAM: {0} GB / {1} stick(s) - {2}" -f $s.RamGb, $s.RamSticks, $s.RamChannels)
    }
    Write-Ok ("SSD: {0} - {1}" -f $s.DiskName, $s.DiskHealth)
    Write-Ok ("C: free: {0} GB" -f $s.FreeGb)
    Write-Ok ("Power plan: {0}" -f $s.PowerPlan)
    if ($s.RebootPending) {
        Write-Warn "Restart pending"
    } else {
        Write-Ok "No pending restart"
    }
}
