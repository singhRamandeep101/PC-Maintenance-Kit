#Requires -Version 5.1
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\PathHelpers.Tests.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not (Test-Path (Join-Path $Root 'lib\Core.ps1'))) {
    $Root = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not (Test-Path (Join-Path $Root 'lib\Core.ps1'))) {
        $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    }
}

$Script:AppRoot = $Root
. (Join-Path $Root 'lib\Core.ps1')
. (Join-Path $Root 'lib\Extras.ps1')

$failed = 0
function Assert-True($cond, $msg) {
    if ($cond) { Write-Host "PASS: $msg" -ForegroundColor Green }
    else { Write-Host "FAIL: $msg" -ForegroundColor Red; $script:failed++ }
}

$versionFile = Join-Path $Root 'VERSION'
Assert-True (Test-Path -LiteralPath $versionFile) 'VERSION file exists'
$fileVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
Assert-True ($Script:AppVersion -eq $fileVersion) ("AppVersion matches VERSION ($fileVersion)")

Assert-True ($null -eq (Join-PathSafe $null 'a')) 'Join-PathSafe null base -> null'
Assert-True ($null -eq (Join-PathSafe '' 'a')) 'Join-PathSafe empty base -> null'
$joined = Join-PathSafe 'C:\Steam' 'steamapps\downloading'
Assert-True ($joined -eq 'C:\Steam\steamapps\downloading' -or $joined -eq 'C:\Steam/steamapps/downloading') 'Join-PathSafe combines'

Assert-True (-not (Test-PathSafe $null)) 'Test-PathSafe null -> false'
Assert-True (-not (Test-PathSafe '')) 'Test-PathSafe empty -> false'
Assert-True (Test-PathSafe $env:SystemRoot) 'Test-PathSafe SystemRoot -> true'

# Missing drive must not throw. Pick a letter that really is unused on this box
# so the assertion never depends on the developer's drive layout.
$usedLetters = @(Get-PSDrive -PSProvider FileSystem -EA SilentlyContinue | ForEach-Object { $_.Name.ToUpperInvariant() })
$freeLetter = @([char[]]'DEFGHIJKLMNOPQRSTUVWXYZ' | Where-Object { $usedLetters -notcontains ([string]$_) }) | Select-Object -First 1
if (-not $freeLetter) { $freeLetter = 'Z' }
$err = $null
try {
    $dl = Join-PathSafe ("{0}:\Steam" -f $freeLetter) 'steamapps\downloading'
    $tp = Test-PathSafe $dl
    Assert-True ($dl -like ("{0}:\*" -f $freeLetter)) 'Join-PathSafe missing drive still returns path string'
    Assert-True ($tp -eq $false) 'Test-PathSafe missing drive path -> false'
} catch {
    $err = $_
}
Assert-True ($null -eq $err) 'Missing drive helpers do not throw'

$steamErr = $null
$steamPaths = $null
try {
    $steamPaths = @(Get-SteamDownloadingPaths)
} catch {
    $steamErr = $_
}
Assert-True ($null -eq $steamErr) 'Get-SteamDownloadingPaths does not throw'
Assert-True ($null -ne $steamPaths) 'Get-SteamDownloadingPaths returns a collection'
$steamBad = @($steamPaths | Where-Object { [string]::IsNullOrWhiteSpace($_) -or -not (Test-PathSafe $_) })
Assert-True ($steamBad.Count -eq 0) 'Get-SteamDownloadingPaths only returns existing paths'

# ---- Destructive-path safety (the guard in front of every recursive delete) ----
Assert-True (-not (Test-SafeCleanupPath $null)) 'Unsafe: null path'
Assert-True (-not (Test-SafeCleanupPath '')) 'Unsafe: empty path'
Assert-True (-not (Test-SafeCleanupPath '   ')) 'Unsafe: whitespace path'
Assert-True (-not (Test-SafeCleanupPath 'C:\')) 'Unsafe: drive root'
Assert-True (-not (Test-SafeCleanupPath 'C:')) 'Unsafe: bare drive'
Assert-True (-not (Test-SafeCleanupPath $env:SystemRoot)) 'Unsafe: %SystemRoot%'
Assert-True (-not (Test-SafeCleanupPath $env:USERPROFILE)) 'Unsafe: %USERPROFILE%'
Assert-True (-not (Test-SafeCleanupPath $env:LOCALAPPDATA)) 'Unsafe: %LOCALAPPDATA%'
Assert-True (-not (Test-SafeCleanupPath $env:APPDATA)) 'Unsafe: %APPDATA%'
Assert-True (-not (Test-SafeCleanupPath $env:ProgramFiles)) 'Unsafe: Program Files'
Assert-True (-not (Test-SafeCleanupPath $env:ProgramData)) 'Unsafe: ProgramData'
Assert-True (-not (Test-SafeCleanupPath (Join-Path $env:SystemDrive '\Users'))) 'Unsafe: C:\Users'
Assert-True (-not (Test-SafeCleanupPath (Join-Path $env:USERPROFILE 'Documents'))) 'Unsafe: Documents'
Assert-True (-not (Test-SafeCleanupPath (Join-Path $env:SystemRoot 'System32'))) 'Unsafe: System32'
Assert-True (-not (Test-SafeCleanupPath '\\server\share')) 'Unsafe: UNC share root'
Assert-True (-not (Test-SafeCleanupPath (Join-Path $env:SystemRoot '..'))) 'Unsafe: traversal back to drive root'

Assert-True (Test-SafeCleanupPath (Join-Path $env:SystemRoot 'Temp')) 'Safe: C:\Windows\Temp'
Assert-True (Test-SafeCleanupPath (Join-Path $env:LOCALAPPDATA 'Temp')) 'Safe: LocalAppData\Temp'
Assert-True (Test-SafeCleanupPath (Join-Path $env:LOCALAPPDATA 'D3DSCache')) 'Safe: shader cache'
Assert-True (Test-SafeCleanupPath '\\server\share\cache') 'Safe: UNC folder below share root'

# The guard must actually be wired into the delete primitive
Assert-True ((Remove-OldFilesInPath -Path '' -OlderThanDays 0) -eq 0) 'Remove-OldFilesInPath refuses empty path'
Assert-True ((Remove-OldFilesInPath -Path '   ' -OlderThanDays 0) -eq 0) 'Remove-OldFilesInPath refuses whitespace path'

# ---- Behavioral cleanup: old files go, recent files stay ----
$cleanRoot = Join-Path $env:TEMP ('pcmk-clean-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $cleanRoot -Force | Out-Null
$oldFile = Join-Path $cleanRoot 'old.log'
$newFile = Join-Path $cleanRoot 'new.log'
Set-Content -LiteralPath $oldFile -Value 'stale' -Encoding ASCII
Set-Content -LiteralPath $newFile -Value 'fresh' -Encoding ASCII
(Get-Item -LiteralPath $oldFile).LastWriteTime = (Get-Date).AddDays(-10)
$emptyDir = Join-Path $cleanRoot 'emptydir'
New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
$freedBytes = Remove-OldFilesInPath -Path $cleanRoot -OlderThanDays 2 -DeleteFoldersToo
Assert-True (-not (Test-Path -LiteralPath $oldFile)) 'Cleanup removes files older than the cutoff'
Assert-True (Test-Path -LiteralPath $newFile) 'Cleanup keeps files newer than the cutoff'
Assert-True (-not (Test-Path -LiteralPath $emptyDir)) 'Cleanup removes emptied folders'
Assert-True ($freedBytes -gt 0) 'Cleanup reports freed bytes'
Assert-True (Test-Path -LiteralPath $cleanRoot) 'Cleanup never deletes the root it was given'
Remove-Item -LiteralPath $cleanRoot -Recurse -Force -EA SilentlyContinue

# Read-only files must still delete (Remove-Item -Force, not FileInfo.Delete)
$roRoot = Join-Path $env:TEMP ('pcmk-ro-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $roRoot -Force | Out-Null
$roFile = Join-Path $roRoot 'readonly.tmp'
Set-Content -LiteralPath $roFile -Value 'x' -Encoding ASCII
(Get-Item -LiteralPath $roFile).IsReadOnly = $true
$roFreed = Remove-OldFilesInPath -Path $roRoot -OlderThanDays 0 -DeleteFoldersToo
Assert-True (-not (Test-Path -LiteralPath $roFile)) 'Cleanup deletes read-only files'
Assert-True ($roFreed -gt 0) 'Cleanup reports bytes for read-only deletes'
Remove-Item -LiteralPath $roRoot -Recurse -Force -EA SilentlyContinue

$settings = Get-DefaultGuiSettings
Assert-True ($settings.HomeWU -eq $false) 'Default HomeWU is false'
Assert-True ($settings.HomeWinget -eq $false) 'Default HomeWinget is false'
Assert-True ($settings.CleanWuCache -eq $false) 'Default CleanWuCache is false'
Assert-True ($settings.CleanEpic -eq $false) 'Default CleanEpic is false'

$settingsPath = Get-GuiSettingsPath
$appDataPrefix = Join-Path $env:LOCALAPPDATA 'PC-Maintenance-Kit'
Assert-True ($settingsPath.StartsWith($appDataPrefix)) 'GUI settings live under LocalAppData'

Apply-ModeFlags Full
Assert-True ($Script:DoWinUpdate -eq $false) 'Weekly Full leaves Windows Update off'
Assert-True ($Script:DoWinget -eq $false) 'Weekly Full leaves winget off'
Assert-True ($Script:DoCleanup -eq $true) 'Weekly Full runs cleanup'
Assert-True ($Script:DoWuCacheWipe -eq $false) 'Weekly Full leaves WU cache wipe off'
Reset-MaintenanceFlags
Assert-True ($Script:DoWuCacheWipe -eq $false) 'Reset-MaintenanceFlags keeps WU cache wipe off'

$Script:DoWuCacheWipe = $true
Apply-ModeFlags Full
Assert-True ($Script:DoWuCacheWipe -eq $false) 'Apply-ModeFlags Full clears sticky DoWuCacheWipe'
$Script:DoWuCacheWipe = $true
Apply-ModeFlags CleanupOnly
Assert-True ($Script:DoWuCacheWipe -eq $false) 'Apply-ModeFlags CleanupOnly clears sticky DoWuCacheWipe'
$Script:DoWuCacheWipe = $true
Apply-ModeFlags FullRepair
Assert-True ($Script:DoWuCacheWipe -eq $false) 'Apply-ModeFlags FullRepair clears sticky DoWuCacheWipe'
Reset-MaintenanceFlags

Apply-ModeFlags Repair
Assert-True ($Script:DoRepair -eq $true) 'Repair mode enables DISM/SFC'
Assert-True ($Script:DoCleanup -eq $false) 'Repair mode skips cleanup'
Reset-MaintenanceFlags

Apply-ModeFlags FullRepair
Assert-True ($Script:DoRepair -eq $true -and $Script:DoWinUpdate -eq $true) 'FullRepair enables repair + WU'
Reset-MaintenanceFlags

$browserMap = Get-BrowserCachePaths
Assert-True ($browserMap -is [System.Collections.IDictionary] -or $browserMap -is [hashtable] -or $browserMap.GetType().Name -eq 'OrderedDictionary') 'Get-BrowserCachePaths returns a map'
$browserErr = $null
try { $null = Get-BrowserCachePaths } catch { $browserErr = $_ }
Assert-True ($null -eq $browserErr) 'Get-BrowserCachePaths does not throw'

# Root ShaderCache should be discoverable when present under a fake User Data tree
$fakeUd = Join-Path $env:TEMP ('pcmk-chrome-ud-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $fakeUd 'ShaderCache') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $fakeUd 'Guest Profile\Cache') -Force | Out-Null
$chromPaths = @(Get-ChromiumProfileCachePaths -UserDataRoot $fakeUd)
Assert-True ($chromPaths -contains (Join-Path $fakeUd 'ShaderCache')) 'Chromium root ShaderCache included'
Assert-True ($chromPaths -contains (Join-Path $fakeUd 'Guest Profile\Cache')) 'Guest Profile Cache included'
Remove-Item -LiteralPath $fakeUd -Recurse -Force -EA SilentlyContinue

$previewErr = $null
$preview = $null
try {
    $preview = Get-CleanupPreview -TempOlderThanDays 2 -Shaders $false -Steam $false -Epic $false -Riot $false -WuCache $true
} catch {
    $previewErr = $_
}
Assert-True ($null -eq $previewErr) 'Get-CleanupPreview does not throw'
Assert-True ($null -ne $preview -and $null -ne $preview.Rows) 'Get-CleanupPreview returns rows'
Assert-True (@($preview.Rows).Count -gt 0) 'Get-CleanupPreview returns at least one row'
$badRows = @($preview.Rows | Where-Object { [string]::IsNullOrWhiteSpace($_.Label) })
Assert-True ($badRows.Count -eq 0) 'Every cleanup preview row is labelled'

# WuCache is opt-in: off must never produce a WU row, regardless of machine state
$previewNoWu = Get-CleanupPreview -TempOlderThanDays 2 -Shaders $false -Steam $false -Epic $false -Riot $false -WuCache $false
$wuRowsOff = @($previewNoWu.Rows | Where-Object { $_.Label -eq 'WU Download Cache' })
Assert-True ($wuRowsOff.Count -eq 0) 'Cleanup preview omits WU cache when not requested'

Assert-True ((Compare-AppVersion -Current '5.1.7' -Other '5.1.6') -gt 0) 'Compare-AppVersion detects local newer'
Assert-True ((Compare-AppVersion -Current '5.1.6' -Other '5.1.7') -lt 0) 'Compare-AppVersion detects update available'
Assert-True ((Compare-AppVersion -Current '5.2.4' -Other '5.2.4') -eq 0) 'Compare-AppVersion equal versions'
Assert-True ((Compare-AppVersion -Current '5.3.0' -Other 'v5.3.0') -eq 0) 'Compare-AppVersion ignores leading v'
Assert-True ((Compare-AppVersion -Current '5.3.0' -Other 'v5.3.0-rc1') -eq 0) 'Compare-AppVersion ignores prerelease suffix'
Assert-True ((Compare-AppVersion -Current '5.3.1' -Other 'v5.3.0-rc1') -gt 0) 'Compare-AppVersion compares numeric core only'
Assert-True ((Compare-AppVersion -Current '5.3.0' -Other 'not-a-version') -eq 0) 'Compare-AppVersion is inert on garbage input'
$extrasRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Extras.ps1') -Raw
Assert-True ($extrasRaw -match "NewerThanRelease") 'Update check has NewerThanRelease status'
Assert-True ($null -ne (Get-Command Get-ExpectedSha256Text -EA SilentlyContinue)) 'Get-ExpectedSha256Text exists'
Assert-True ($null -eq (Get-ExpectedSha256Text 'abc')) 'Get-ExpectedSha256Text rejects short text'
$sampleHash = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
Assert-True ((Get-ExpectedSha256Text "sha256:$sampleHash") -eq $sampleHash) 'Get-ExpectedSha256Text parses digest'
Assert-True ((Get-ExpectedSha256Text "$sampleHash  file.zip") -eq $sampleHash) 'Get-ExpectedSha256Text parses checksum line'

# Discord JSON: empty object must remain valid after toggle; existing keys stay surgical
$discordProbe = Join-Path $env:TEMP ('pcmk-discord-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
Set-Content -LiteralPath $discordProbe -Value '{}' -Encoding UTF8
. (Join-Path $Root 'lib\Gaming.ps1')
function Get-DiscordSettingsPath { $discordProbe }
Set-DiscordHardwareAcceleration $false
$discordRaw = Get-Content -LiteralPath $discordProbe -Raw
$discordObj = $null
$discordParseErr = $null
try { $discordObj = $discordRaw | ConvertFrom-Json } catch { $discordParseErr = $_ }
Assert-True ($null -eq $discordParseErr) 'Discord settings remain valid JSON after toggle'
Assert-True ($discordObj.hardwareAcceleration -eq $false) 'Discord hardwareAcceleration set to false'

Set-Content -LiteralPath $discordProbe -Value "{`r`n  `"KEEP_ME`": true,`r`n  `"hardwareAcceleration`": true`r`n}" -Encoding UTF8
Set-DiscordHardwareAcceleration $false
$discordRaw2 = Get-Content -LiteralPath $discordProbe -Raw
Assert-True ($discordRaw2 -match '"KEEP_ME"\s*:\s*true') 'Discord surgical edit preserves other keys'
Assert-True ($discordRaw2 -match '"hardwareAcceleration"\s*:\s*false') 'Discord surgical edit flips acceleration'
Assert-True (([regex]::Matches($discordRaw2, '"hardwareAcceleration"\s*:')).Count -eq 1) 'Discord has single hardwareAcceleration key'

# Non-boolean existing value must be replaced, not duplicated
Set-Content -LiteralPath $discordProbe -Value "{`r`n  `"hardwareAcceleration`": null`r`n}" -Encoding UTF8
Set-DiscordHardwareAcceleration $true
$discordRaw3 = Get-Content -LiteralPath $discordProbe -Raw
Assert-True (([regex]::Matches($discordRaw3, '"hardwareAcceleration"\s*:')).Count -eq 1) 'Discord null value replaced without duplicate'
Assert-True ($discordRaw3 -match '"hardwareAcceleration"\s*:\s*true') 'Discord null value flipped to true'
Remove-Item -LiteralPath $discordProbe -Force -EA SilentlyContinue

# ---- Settings round-trip (redirected away from the real profile) ----
$settingsProbe = Join-Path $env:TEMP ('pcmk-settings-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
function Get-GuiSettingsPath { $settingsProbe }

function New-FakeCheck([bool]$Checked) { return [pscustomobject]@{ Checked = $Checked } }
$fakeControls = [pscustomobject]@{
    ChkHomeRestore  = New-FakeCheck $false
    ChkHomeShader   = New-FakeCheck $true
    ChkHomeGaming   = New-FakeCheck $false
    ChkHomeWU       = New-FakeCheck $true
    ChkHomeWinget   = New-FakeCheck $false
    DaysNum         = [pscustomobject]@{ Value = 7 }
    ChkCleanShader  = New-FakeCheck $false
    ChkSteam        = New-FakeCheck $true
    ChkEpic         = New-FakeCheck $false
    ChkRiot         = New-FakeCheck $true
    ChkWuCache      = New-FakeCheck $false
    ChkUpdRestore   = New-FakeCheck $false
    ChkUpdWU        = New-FakeCheck $false
    ChkUpdWinget    = New-FakeCheck $true
    ChkRepRestore   = New-FakeCheck $false
}

# Keys with no control behind them (and forward-compat keys) must survive a save
$Script:LoadedGuiSettings = [ordered]@{
    CheckUpdatesOnStart = $false
    FutureOnlyKey       = 'keep-me'
}
Save-GuiSettings $fakeControls
Assert-True (Test-Path -LiteralPath $settingsProbe) 'Save-GuiSettings writes the settings file'
$savedJson = $null
$savedErr = $null
try { $savedJson = (Get-Content -LiteralPath $settingsProbe -Raw) | ConvertFrom-Json } catch { $savedErr = $_ }
Assert-True ($null -eq $savedErr) 'Saved settings are valid JSON'
Assert-True ($savedJson.HomeWU -eq $true) 'Save-GuiSettings persists control values'
Assert-True ($savedJson.TempOlderDays -eq 7) 'Save-GuiSettings persists numeric values'
Assert-True ($savedJson.CheckUpdatesOnStart -eq $false) 'Save-GuiSettings keeps control-less settings'
Assert-True ($savedJson.FutureOnlyKey -eq 'keep-me') 'Save-GuiSettings keeps forward-compat keys'

$loaded = Load-GuiSettings
Assert-True ($loaded.HomeWU -eq $true) 'Load-GuiSettings round-trips saved values'
Assert-True ($loaded.TempOlderDays -eq 7) 'Load-GuiSettings round-trips numbers'
Assert-True ($loaded.FutureOnlyKey -eq 'keep-me') 'Load-GuiSettings preserves unknown keys'
Assert-True ($loaded.RepRestore -eq $false) 'Load-GuiSettings reflects saved checkbox state'

# Apply must clamp out-of-range values and not abort on a single bad control
$applyTargets = [pscustomobject]@{
    ChkHomeRestore  = New-FakeCheck $false
    ChkHomeShader   = New-FakeCheck $false
    ChkHomeGaming   = New-FakeCheck $false
    ChkHomeWU       = New-FakeCheck $false
    ChkHomeWinget   = New-FakeCheck $false
    DaysNum         = [pscustomobject]@{ Value = 0 }
    ChkCleanShader  = New-FakeCheck $false
    ChkSteam        = New-FakeCheck $false
    ChkEpic         = New-FakeCheck $false
    ChkRiot         = New-FakeCheck $false
    ChkWuCache      = New-FakeCheck $false
    ChkUpdRestore   = New-FakeCheck $false
    ChkUpdWU        = New-FakeCheck $false
    ChkUpdWinget    = New-FakeCheck $false
    ChkRepRestore   = New-FakeCheck $false
}
$clamped = Get-DefaultGuiSettings
$clamped.TempOlderDays = 999
$clamped.HomeWU = $true
Apply-GuiSettings -Controls $applyTargets -Settings $clamped
Assert-True ($applyTargets.DaysNum.Value -eq 30) 'Apply-GuiSettings clamps TempOlderDays to 30'
Assert-True ($applyTargets.ChkHomeWU.Checked -eq $true) 'Apply-GuiSettings restores checkbox state'

# A missing control must not stop the remaining settings from being applied
$partial = [pscustomobject]@{
    ChkHomeRestore = New-FakeCheck $false
    ChkRepRestore  = New-FakeCheck $false
    DaysNum        = [pscustomobject]@{ Value = 0 }
}
$partialSettings = Get-DefaultGuiSettings
$partialSettings.HomeRestore = $true
$partialSettings.RepRestore = $true
Apply-GuiSettings -Controls $partial -Settings $partialSettings
Assert-True ($partial.ChkHomeRestore.Checked -eq $true) 'Apply-GuiSettings applies the first setting'
Assert-True ($partial.ChkRepRestore.Checked -eq $true) 'Apply-GuiSettings continues past missing controls'

Remove-Item -LiteralPath $settingsProbe -Force -EA SilentlyContinue
$Script:LoadedGuiSettings = $null

. (Join-Path $Root 'lib\Device.ps1')
$summaryErr = $null
$summary = $null
try {
    $summary = Get-DeviceSummary
} catch {
    $summaryErr = $_
}
Assert-True ($null -eq $summaryErr) 'Get-DeviceSummary does not throw'
Assert-True ($null -ne $summary -and $summary.Cpu) 'Get-DeviceSummary returns CPU'
$summary2 = Get-DeviceSummary
Assert-True ([object]::ReferenceEquals($summary, $summary2)) 'Get-DeviceSummary cache returns same object'

# Reboot-pending must use hard WU/CBS signals only. Stale PendingFileRenameOperations
# (Gaming Services / InstallShield temp leftovers) must not tank Hygiene forever.
$ri = Get-RebootPendingInfo
Assert-True ($null -ne $ri) 'Get-RebootPendingInfo returns object'
Assert-True ($ri.PSObject.Properties.Name -contains 'Pending') 'Get-RebootPendingInfo has Pending'
Assert-True ($ri.PSObject.Properties.Name -contains 'Reasons') 'Get-RebootPendingInfo has Reasons'
Assert-True (((Test-RebootPending) -is [bool])) 'Test-RebootPending returns bool'
$hardWu = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
$hardCbs = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
$hardOrch = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\RebootRequired"
$hardAny = $hardWu -or $hardCbs -or $hardOrch
Assert-True (([bool]$ri.Pending) -eq $hardAny) 'Reboot pending matches hard WU/CBS/Orchestrator keys only'
Assert-True (([bool](Test-RebootPending)) -eq ([bool]$ri.Pending)) 'Test-RebootPending matches Get-RebootPendingInfo.Pending'
Assert-True ($ri.Reasons -is [System.Array] -or $ri.Reasons -is [string[]] -or $null -ne $ri.Reasons) 'Get-RebootPendingInfo.Reasons is a collection'
if ($ri.Pending) {
    Assert-True (@($ri.Reasons).Count -gt 0) 'Pending reboot includes at least one reason'
} else {
    Assert-True (@($ri.Reasons).Count -eq 0) 'No pending reboot means empty Reasons'
}
$coreRebootRaw = Get-Content (Join-Path $Root 'lib\Core.ps1') -Raw
Assert-True ($coreRebootRaw -match 'PendingFileRenameOperations is intentionally ignored') 'Core documents ignoring noisy PendingFileRenameOperations'

Assert-True ((Format-UiByteSize 0) -eq '0 B') 'Format-UiByteSize 0 B'
Assert-True ((Format-UiByteSize 512) -eq '512 B') 'Format-UiByteSize bytes'
Assert-True ((Format-UiByteSize 2048) -eq '2 KB') 'Format-UiByteSize KB'
Assert-True ((Format-UiByteSize 5MB) -eq '5 MB') 'Format-UiByteSize MB'
Assert-True ((Format-UiByteSize 1536MB) -match 'GB') 'Format-UiByteSize GB'
Assert-True ($null -ne (Get-Command Update-UiSubProgress -EA SilentlyContinue)) 'Update-UiSubProgress exists'
Assert-True ($null -ne (Get-Command Clear-HardwareProbeCaches -EA SilentlyContinue)) 'Clear-HardwareProbeCaches exists'
$free1 = Get-CFreeGB
$free2 = Get-CFreeGB
Assert-True ($free1 -eq $free2) 'Get-CFreeGB cache returns stable value'
$prot1 = Get-ProtectedCleanupPaths
$prot2 = Get-ProtectedCleanupPaths
Assert-True ([object]::ReferenceEquals($prot1, $prot2)) 'Get-ProtectedCleanupPaths caches the protected list'

. (Join-Path $Root 'lib\Score.ps1')
$scoreErr = $null
$optScore = $null
try {
    $optScore = Get-GamingOptimizationScore -Refresh
} catch {
    $scoreErr = $_
}
Assert-True ($null -eq $scoreErr) 'Get-GamingOptimizationScore does not throw'
Assert-True ($null -ne $optScore) 'Get-GamingOptimizationScore returns object'
Assert-True ($optScore.Score -ge 0 -and $optScore.Score -le 100) 'Score is 0..100'
Assert-True ($null -ne $optScore.Categories -and $optScore.Categories.Count -ge 5) 'Score has categories'
Assert-True ($null -ne $optScore.BiggestLimiter) 'Score has BiggestLimiter'
Assert-True ($null -ne $optScore.TopFixes) 'Score has TopFixes'
Assert-True ($null -ne $optScore.HardwareReadiness) 'Score has HardwareReadiness'
$weightSum = ($optScore.Categories | Measure-Object -Property Weight -Sum).Sum
Assert-True ([math]::Abs($weightSum - 1.0) -lt 0.001) 'Category weights sum to 1.0'
$hygCat = @($optScore.Categories | Where-Object { $_.Name -eq 'Hygiene' } | Select-Object -First 1)
Assert-True ($null -ne $hygCat) 'Score includes Hygiene category'
if (-not $hardAny) {
    Assert-True ($hygCat.Score -eq 100) 'Hygiene is 100 when no hard reboot signal'
    $rebootCheck = @($optScore.Checks | Where-Object { $_.Id -eq 'reboot_pending' } | Select-Object -First 1)
    Assert-True ($null -ne $rebootCheck -and $rebootCheck.Status -eq 'Good') 'reboot_pending is Good without hard reboot signal'
}
$hagsCheck = @($optScore.Checks | Where-Object { $_.Id -eq 'hags' } | Select-Object -First 1)
Assert-True ($null -ne $hagsCheck -and $hagsCheck.Points -eq $hagsCheck.Max) 'HAGS does not soft-cap points when off/unknown'
$optScore2 = Get-GamingOptimizationScore
Assert-True ([object]::ReferenceEquals($optScore, $optScore2)) 'Optimization score cache returns same object'
$shortTxt = Format-OptimizationScoreText -ScoreObject $optScore -Short
Assert-True ($shortTxt -match 'Opt score:') 'Format-OptimizationScoreText -Short works'

# Channel label scoring must not treat "Likely dual" as confirmed Dual
Assert-True ('Dual (or more)' -match '^Dual') 'Confirmed Dual label matches ^Dual'
Assert-True ('Likely dual (verify in Task Manager)' -notmatch '^Dual') 'Likely dual does not match ^Dual'
Assert-True ('Single-channel (add matching stick)' -match 'Single') 'Single-channel still detected'

# Grade thresholds are user-facing copy - pin them
Assert-True ((Get-OptimizationGrade 100) -eq 'Excellent') 'Grade 100 -> Excellent'
Assert-True ((Get-OptimizationGrade 85) -eq 'Excellent') 'Grade 85 -> Excellent'
Assert-True ((Get-OptimizationGrade 84) -eq 'Good') 'Grade 84 -> Good'
Assert-True ((Get-OptimizationGrade 70) -eq 'Good') 'Grade 70 -> Good'
Assert-True ((Get-OptimizationGrade 69) -eq 'Needs work') 'Grade 69 -> Needs work'
Assert-True ((Get-OptimizationGrade 50) -eq 'Needs work') 'Grade 50 -> Needs work'
Assert-True ((Get-OptimizationGrade 49) -eq 'Critical') 'Grade 49 -> Critical'
Assert-True ((Get-OptimizationGrade 0) -eq 'Critical') 'Grade 0 -> Critical'

# Every check must carry a usable shape, and no fix may point at an unknown action
$validStatus = @('Good', 'Warn', 'Bad', 'Unknown')
$validActions = @('GamingOptimize', 'OpenStorage', 'CopyRamTip', 'OpenStartup', 'OpenDisplay', 'None')
$badChecks = @($optScore.Checks | Where-Object {
    [string]::IsNullOrWhiteSpace($_.Id) -or
    [string]::IsNullOrWhiteSpace($_.Title) -or
    ($validStatus -notcontains $_.Status) -or
    ($validActions -notcontains $_.FixAction) -or
    ($_.Points -lt 0) -or ($_.Points -gt $_.Max)
})
Assert-True ($badChecks.Count -eq 0) 'Every score check has a valid id, status, action and point range'
$badFixes = @($optScore.TopFixes | Where-Object { $_.Status -ne 'Bad' -and $_.Status -ne 'Warn' })
Assert-True ($badFixes.Count -eq 0) 'TopFixes only lists Bad/Warn checks'
Assert-True (@($optScore.TopFixes).Count -le 3) 'TopFixes is capped at three'
$badCats = @($optScore.Categories | Where-Object { $_.Score -lt 0 -or $_.Score -gt 100 })
Assert-True ($badCats.Count -eq 0) 'Every category score is 0..100'
$limiterNames = @($optScore.Categories | ForEach-Object { $_.Name })
Assert-True ($limiterNames -contains $optScore.BiggestLimiter) 'BiggestLimiter names a real category'
$lowestScore = ($optScore.Categories | Measure-Object -Property Score -Minimum).Minimum
$limiterScore = ($optScore.Categories | Where-Object { $_.Name -eq $optScore.BiggestLimiter } | Select-Object -First 1).Score
Assert-True ($limiterScore -eq $lowestScore) 'BiggestLimiter is the lowest-scoring category'

# lib scripts are discovered from disk so a new file cannot skip the syntax gate
$parseFiles = @('PC-Maintenance.ps1', 'Get.ps1', 'Build-Release.ps1')
$parseFiles += @(
    Get-ChildItem -LiteralPath (Join-Path $Root 'lib') -Filter *.ps1 -File |
        ForEach-Object { Join-Path 'lib' $_.Name }
)
Assert-True ($parseFiles.Count -ge 9) 'Parse list discovered all lib scripts'
foreach ($rel in $parseFiles) {
    $parsePath = Join-Path $Root $rel
    $errs = $null
    $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($parsePath, [ref]$toks, [ref]$errs)
    $ok = -not $errs -or $errs.Count -eq 0
    Assert-True $ok ("Parse $rel")
}

$getRaw = Get-Content -LiteralPath (Join-Path $Root 'Get.ps1') -Raw
Assert-True ($getRaw -match 'Test-Sha256File') 'Get.ps1 verifies SHA256'
Assert-True ($getRaw -match 'Refusing to install without integrity') 'Get.ps1 fails closed without SHA256'
Assert-True ($getRaw -notmatch 'refs/heads/main\.zip') 'Get.ps1 no longer falls back to main.zip'
Assert-True ($getRaw -match 'Could not fetch GitHub release info') 'Get.ps1 surfaces network/API errors'
Assert-True ($getRaw -match 'zip\.digest') 'Get.ps1 can fall back to asset digest'
$coreRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Core.ps1') -Raw
Assert-True ($coreRaw -match 'upgrade --all --source winget --silent') 'Core.ps1 uses fast bulk winget upgrade'
Assert-True ($coreRaw -match 'pin add --id') 'Core.ps1 pins skip-list before bulk upgrade'
Assert-True ($coreRaw -match 'pin remove --id') 'Core.ps1 removes temporary pins after bulk upgrade'
Assert-True ($coreRaw -match 'Invoke-WithUiModal') 'Core.ps1 has Invoke-WithUiModal'
Assert-True ($coreRaw -match 'Show-RebootRecommendedDialog') 'Core.ps1 has the reboot dialog'
# Every recursive delete must route through the safety guard
Assert-True ($coreRaw -match 'Assert-SafeCleanupPath') 'Core.ps1 guards deletes with Assert-SafeCleanupPath'
Assert-True ($null -ne (Get-Command Test-SafeCleanupPath -EA SilentlyContinue)) 'Test-SafeCleanupPath is exported'
# Services stopped for the WU cache wipe must be restarted in a finally
Assert-True ($coreRaw -match '(?s)Stop-Service wuauserv.*?finally.*?Start-Service wuauserv') 'WU services restart in a finally block'

$guiRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Gui.ps1') -Raw
Assert-True ($guiRaw -match 'Invoke-GuiCleanupSteps') 'Gui exposes shared cleanup steps'
Assert-True ($guiRaw -match 'BtnCli') 'GuiBusy list covers the CLI button'
Assert-True ($guiRaw -match 'BtnQuit') 'GuiBusy list covers the Quit button'
Assert-True ($guiRaw -match 'FormClosing') 'Gui blocks close while busy'
Assert-True ($guiRaw -match 'Checking for updates') 'Startup update check runs under GuiBusy'
Assert-True ($guiRaw -match 'Clear-HardwareProbeCaches|Invoke-GuiPanelsRefresh') 'Gui refreshes panels through a shared orchestrator'
Assert-True ($guiRaw -match 'Resolve-GuiRefreshMode') 'Gui chooses refresh mode by action'
Assert-True ($coreRaw -match 'function Clear-HardwareProbeCaches') 'Core exposes Clear-HardwareProbeCaches'
Assert-True ($coreRaw -match 'EnumerateFiles') 'Cleanup streams files via EnumerateFiles'
Assert-True ($guiRaw -match 'CleanupPreviewCache') 'Gui caches recent cleanup previews'
Assert-True ($guiRaw -match 'add_ThreadException') 'Gui installs an unhandled-exception perimeter'
# Restart must never fire from a DoEvents-delivered click during a job
$restartClick = ($guiRaw -split 'btnRestartNow\.Add_Click')[1]
Assert-True ($null -ne $restartClick -and ($restartClick -split 'Invoke-RestartComputerConfirmed')[0] -match 'GuiBusy') 'Restart button is guarded while busy'

$extrasRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Extras.ps1') -Raw
Assert-True ($extrasRaw -match 'Prefer published \.sha256 file') 'Self-update prefers .sha256 before digest'
Assert-True ($extrasRaw -match 'DigestSha256') 'Release info carries DigestSha256'
Assert-True ($extrasRaw -match 'Refusing to install update') 'Self-update fails closed without a checksum'
# Backup + rollback must exist in the generated apply script
Assert-True ($extrasRaw -match 'Test-InstallHealthy') 'Self-update health-checks the new install'
Assert-True ($extrasRaw -match 'Rolled back to the previous version') 'Self-update rolls back a bad update'
Assert-True ($extrasRaw -match 'PC-Maintenance-Kit-backup') 'Self-update snapshots the current install'
Assert-True ($extrasRaw -match 'Remove-StaleScripts') 'Self-update purges scripts removed from the new release'

. (Join-Path $Root 'lib\Care.ps1')
$presets = Get-CarePresetMap
Assert-True ($presets.Contains('Gamer')) 'Care presets include Gamer'
Assert-True ($presets.Contains('Quiet')) 'Care presets include Quiet'
Assert-True ($presets.Contains('Full')) 'Care presets include Full'
Assert-True ($presets.Gamer.HomeWU -eq $false) 'Gamer preset leaves WU off'
Assert-True ($presets.Quiet.HomeGaming -eq $false) 'Quiet preset leaves gaming opts off'
Assert-True ($presets.Full.HomeWinget -eq $true) 'Full preset enables winget'
Assert-True ($Script:WeeklyCareTaskName -match 'Weekly') 'Weekly care task name is set'

$pmRaw = Get-Content -LiteralPath (Join-Path $Root 'PC-Maintenance.ps1') -Raw
Assert-True ($pmRaw -match "ValidateSet\([^\)]*'Scheduled'") 'Entry script accepts -Mode Scheduled'
Assert-True ($pmRaw -match 'lib\\Care\.ps1') 'Entry script loads Care.ps1'
Assert-True ($pmRaw -match 'Apply-ScheduledCareFlags') 'Scheduled mode applies care flags'

$guiRaw2 = Get-Content -LiteralPath (Join-Path $Root 'lib\Gui.ps1') -Raw
Assert-True ($guiRaw2 -match 'Enable-GuiDpiAwareness') 'GUI enables DPI awareness'
Assert-True ($guiRaw2 -match 'AutoScaleMode]::Dpi') 'Form uses DPI autoscaling'
Assert-True ($guiRaw2 -match 'GuiPages\.ps1') 'GUI loads GuiPages module'
Assert-True ($guiRaw2 -match 'BtnPresetGamer') 'GUI wires care presets'

$pagesRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\GuiPages.ps1') -Raw
Assert-True ($pagesRaw -match 'function Add-GuiHomePage') 'GuiPages has Home builder'
Assert-True ($pagesRaw -match 'function Add-GuiGamingPage') 'GuiPages has Gaming builder'
Assert-True ($pagesRaw -match 'ChkScheduleWeekly') 'Home page has schedule checkbox'
Assert-True ($pagesRaw -match 'GetNewClosure') 'GuiPages Resize handlers capture locals with GetNewClosure'

$buildRaw = Get-Content -LiteralPath (Join-Path $Root 'Build-Release.ps1') -Raw
Assert-True ($buildRaw -match 'Get-FileHash') 'Build-Release.ps1 hashes ZIP'
Assert-True ($buildRaw -match 'VERSION') 'Build-Release.ps1 reads VERSION'

# Build must refuse a -Version that disagrees with the VERSION file
$buildMismatch = $null
try {
    & (Join-Path $Root 'Build-Release.ps1') -Version '0.0.1' | Out-Null
} catch {
    $buildMismatch = $_
}
Assert-True ($null -ne $buildMismatch) 'Build-Release rejects a -Version that does not match VERSION'
Assert-True ($buildMismatch.Exception.Message -match 'does not match VERSION') 'Build-Release explains the version mismatch'

$hashProbe = Join-Path $env:TEMP 'pcmk-hash-probe.txt'
Set-Content -LiteralPath $hashProbe -Value 'pcmk' -Encoding ASCII
$h = (Get-FileHash -LiteralPath $hashProbe -Algorithm SHA256).Hash.ToLowerInvariant()
$sumLine = "{0}  pcmk-hash-probe.txt" -f $h
Assert-True ($sumLine -match '([A-Fa-f0-9]{64})' -and $Matches[1].ToLowerInvariant() -eq $h) 'SHA256 checksum line format'
Remove-Item -LiteralPath $hashProbe -Force -EA SilentlyContinue

if ($failed -gt 0) {
    Write-Host "`n$failed test(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll path helper tests passed." -ForegroundColor Green
exit 0
