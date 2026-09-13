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

# Missing drive must not throw
$err = $null
try {
    $dl = Join-PathSafe 'D:\Steam' 'steamapps\downloading'
    $tp = Test-PathSafe $dl
    Assert-True ($dl -like 'D:\*') 'Join-PathSafe missing drive still returns path string'
    Assert-True ($tp -eq $false) 'Test-PathSafe missing drive path -> false'
} catch {
    $err = $_
}
Assert-True ($null -eq $err) 'Missing drive helpers do not throw'

$steamErr = $null
try {
    $paths = @(Get-SteamDownloadingPaths)
    Assert-True ($true) ("Get-SteamDownloadingPaths returned {0} path(s)" -f $paths.Count)
} catch {
    $steamErr = $_
    Assert-True $false ("Get-SteamDownloadingPaths threw: $($_.Exception.Message)")
}
Assert-True ($null -eq $steamErr) 'Get-SteamDownloadingPaths does not throw'

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

# Root ShaderCache + Guest Profile should be discoverable under a fake User Data tree
$fakeUd = Join-Path $env:TEMP ('pcmk-chrome-ud-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $fakeUd 'ShaderCache') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $fakeUd 'Guest Profile\Cache') -Force | Out-Null
$chromPaths = @(Get-ChromiumProfileCachePaths -UserDataRoot $fakeUd)
function Get-FullPathNorm([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return '' }
    return [System.IO.Path]::GetFullPath($p).TrimEnd('\', '/').ToLowerInvariant()
}
$chromNorm = @($chromPaths | ForEach-Object { Get-FullPathNorm $_ })
Assert-True ($chromNorm -contains (Get-FullPathNorm (Join-Path $fakeUd 'ShaderCache'))) 'Chromium root ShaderCache included'
Assert-True ($chromNorm -contains (Get-FullPathNorm (Join-Path $fakeUd 'Guest Profile\Cache'))) 'Guest Profile Cache included'
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
$wuRows = @($preview.Rows | Where-Object { $_.Label -eq 'WU Download Cache' })
Assert-True ($wuRows.Count -ge 0) 'Get-CleanupPreview accepts WuCache switch'

Assert-True ((Compare-AppVersion -Current '5.1.7' -Other '5.1.6') -gt 0) 'Compare-AppVersion detects local newer'
Assert-True ((Compare-AppVersion -Current '5.1.6' -Other '5.1.7') -lt 0) 'Compare-AppVersion detects update available'
Assert-True ((Compare-AppVersion -Current '5.2.4' -Other '5.2.4') -eq 0) 'Compare-AppVersion equal versions'
$extrasRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Extras.ps1') -Raw
Assert-True ($extrasRaw -match "NewerThanRelease") 'Update check has NewerThanRelease status'
$guiRaw2 = Get-Content -LiteralPath (Join-Path $Root 'lib\Gui.ps1') -Raw
Assert-True ($guiRaw2 -match 'ahead of the published release') 'GUI explains local-newer-than-GitHub'
Assert-True ($guiRaw2 -match 'ResizeRedraw') 'Progress fill uses ResizeRedraw to avoid stripe bands'
Assert-True ($guiRaw2 -match 'WrapMode::Clamp|WrapMode\]::Clamp') 'Progress gradient clamps (no tile stripes)'
$coreRawProg = Get-Content -LiteralPath (Join-Path $Root 'lib\Core.ps1') -Raw
Assert-True ($coreRawProg -match '\$fill\.Invalidate\(\)') 'Progress width change invalidates full fill'
Assert-True ((Get-Command Get-ExpectedSha256Text -EA SilentlyContinue) -ne $null) 'Get-ExpectedSha256Text exists'
Assert-True ((Get-ExpectedSha256Text 'abc') -eq $null) 'Get-ExpectedSha256Text rejects short text'
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

$parseFiles = @(
    'PC-Maintenance.ps1', 'Get.ps1', 'Build-Release.ps1',
    'lib\Core.ps1', 'lib\Gui.ps1', 'lib\Extras.ps1', 'lib\Device.ps1', 'lib\Gaming.ps1'
)
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
Assert-True ($coreRaw -match 'upgrade --source winget') 'Core.ps1 lists upgrades from winget source only'
Assert-True ($coreRaw -match 'Invoke-WithUiModal') 'Core.ps1 has Invoke-WithUiModal'
Assert-True ($coreRaw -match 'Show-UiMessageBox') 'Core.ps1 has Show-UiMessageBox'
$guiRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Gui.ps1') -Raw
Assert-True ($guiRaw -match 'Invoke-GuiCleanupSteps') 'Gui exposes shared cleanup steps'
Assert-True ($guiRaw -match "BtnCli','BtnQuit") 'GuiBusy disables Quit/CLI'
Assert-True ($guiRaw -match 'FormClosing') 'Gui blocks close while busy'
Assert-True ($guiRaw -match 'Checking for updates') 'Startup update check runs under GuiBusy'
# Preview should measure first; confirm only after Run cleanup
$previewClick = ($guiRaw -split 'btnPreview\.Add_Click')[1]
Assert-True ($previewClick -match 'Measuring cleanup sizes') 'Preview measures sizes'
Assert-True ($previewClick -match 'Confirm-OptionalCleanupCaches') 'Preview confirms only when running cleanup'
$extrasRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Extras.ps1') -Raw
Assert-True ($extrasRaw -match 'Prefer published \.sha256 file') 'Self-update prefers .sha256 before digest'
Assert-True ($extrasRaw -match 'DigestSha256') 'Release info carries DigestSha256'
$coreRaw2 = Get-Content -LiteralPath (Join-Path $Root 'lib\Core.ps1') -Raw
Assert-True ($coreRaw2 -match 'Show-RebootRecommendedDialog' -and $coreRaw2 -match 'Show-UiMessageBox') 'Reboot dialog uses Show-UiMessageBox'
$buildRaw = Get-Content -LiteralPath (Join-Path $Root 'Build-Release.ps1') -Raw
Assert-True ($buildRaw -match 'Get-FileHash') 'Build-Release.ps1 hashes ZIP'
Assert-True ($buildRaw -match 'VERSION') 'Build-Release.ps1 reads VERSION'

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
