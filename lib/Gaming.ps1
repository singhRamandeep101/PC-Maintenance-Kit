function Get-GameModeEnabled {
    $v = (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name AutoGameModeEnabled -EA SilentlyContinue).AutoGameModeEnabled
    if ($null -eq $v) { return $null }
    return [int]$v
}

function Set-GameModeEnabled([bool]$Enabled) {
    $path = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    $val = if ($Enabled) { 1 } else { 0 }
    Set-ItemProperty $path -Name AutoGameModeEnabled -Value $val -Type DWord -Force
}

function Get-GameDvrEnabled {
    $v = (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_Enabled -EA SilentlyContinue).GameDVR_Enabled
    if ($null -eq $v) { return $null }
    return [int]$v
}

function Disable-GameDvrCapture {
    Set-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_Enabled -Value 0 -Type DWord -Force -EA SilentlyContinue
    $gdv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
    if (-not (Test-Path $gdv)) { New-Item -Path $gdv -Force | Out-Null }
    Set-ItemProperty $gdv -Name AppCaptureEnabled -Value 0 -Type DWord -Force -EA SilentlyContinue
    Set-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name UseNexusForGameBarEnabled -Value 0 -Type DWord -Force -EA SilentlyContinue
}

function Get-AmdReLiveEnabled {
    $v = (Get-ItemProperty "HKCU:\Software\AMD\DVR" -Name DvrEnabled -EA SilentlyContinue).DvrEnabled
    if ($null -eq $v) { return $null }
    return [int]$v
}

function Disable-AmdReLive {
    $path = "HKCU:\Software\AMD\DVR"
    if (-not (Test-Path $path)) { return $false }
    Set-ItemProperty $path -Name DvrEnabled -Value 0 -Type DWord -Force -EA SilentlyContinue
    return $true
}

function Enable-UltimatePerformancePlan {
    try {
        powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
    } catch { }
    $out = powercfg /list 2>$null | Out-String
    if ($out -match '([0-9a-fA-F-]{36}).*\(Ultimate Performance\)') {
        powercfg /setactive $Matches[1] | Out-Null
        return $true
    }
    $high = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    powercfg /setactive $high 2>$null | Out-Null
    return $false
}

function Get-ActivePowerPlanName {
    try {
        return ((powercfg /getactivescheme) -replace '.*\((.+)\).*', '$1').Trim()
    } catch {
        return "Unknown"
    }
}

function Get-DiscordSettingsPath {
    Join-Path $env:APPDATA "discord\settings.json"
}

function Get-DiscordHardwareAcceleration {
    $p = Get-DiscordSettingsPath
    if (-not (Test-Path $p)) { return $null }
    try {
        $j = Get-Content $p -Raw -EA Stop | ConvertFrom-Json
        if ($null -eq $j.hardwareAcceleration) { return $true }
        return [bool]$j.hardwareAcceleration
    } catch {
        return $null
    }
}

function Set-DiscordHardwareAcceleration([bool]$Enabled) {
    $p = Get-DiscordSettingsPath
    if (-not (Test-Path $p)) { throw "Discord settings.json not found. Is Discord installed?" }

    $raw = [System.IO.File]::ReadAllText($p)
    $valueText = if ($Enabled) { "true" } else { "false" }
    $pattern = '"hardwareAcceleration"\s*:\s*(true|false)'
    if ($raw -match $pattern) {
        $updated = [regex]::Replace($raw, $pattern, ('"hardwareAcceleration": ' + $valueText), 1)
    } else {
        # Insert after opening brace without rewriting the whole JSON tree
        $updated = [regex]::Replace($raw, '^\s*\{', ('{' + "`n  `"hardwareAcceleration`": $valueText,"), 1)
        if ($updated -eq $raw) {
            throw "Could not update Discord settings.json"
        }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($p, $updated, $utf8NoBom)
}

function Invoke-GamingOptimize {
    Write-Step "Gaming optimizations"
    try {
        Set-GameModeEnabled $true
        Write-Ok "Game Mode: On"
    } catch {
        Write-Warn "Game Mode: could not set"
    }

    try {
        Disable-GameDvrCapture
        Write-Ok "Xbox Game DVR / capture: Off"
    } catch {
        Write-Warn "Game DVR: could not set"
    }

    try {
        if (Disable-AmdReLive) {
            Write-Ok "AMD ReLive: Off"
        } else {
            Write-Info "AMD ReLive key not present"
        }
    } catch {
        Write-Warn "AMD ReLive: could not set"
    }

    try {
        $ult = Enable-UltimatePerformancePlan
        $name = Get-ActivePowerPlanName
        if ($ult) {
            Write-Ok "Power plan: $name"
        } else {
            Write-Ok "Power plan set to High/Ultimate where available: $name"
        }
    } catch {
        Write-Warn "Power plan: could not change"
    }

    Write-Info "Tip: use exclusive Fullscreen in games; cap FPS near monitor Hz for smoother 1% lows"
}
