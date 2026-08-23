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

. (Join-Path $Root 'lib\Core.ps1')
. (Join-Path $Root 'lib\Extras.ps1')

$failed = 0
function Assert-True($cond, $msg) {
    if ($cond) { Write-Host "PASS: $msg" -ForegroundColor Green }
    else { Write-Host "FAIL: $msg" -ForegroundColor Red; $script:failed++ }
}

Assert-True ($null -eq (Join-PathSafe $null 'a')) 'Join-PathSafe null base -> null'
Assert-True ($null -eq (Join-PathSafe '' 'a')) 'Join-PathSafe empty base -> null'
$joined = Join-PathSafe 'C:\Steam' 'steamapps\downloading'
Assert-True ($joined -eq 'C:\Steam\steamapps\downloading' -or $joined -eq 'C:\Steam/steamapps\downloading') 'Join-PathSafe combines'

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

$settingsPath = Get-GuiSettingsPath
$appDataPrefix = Join-Path $env:LOCALAPPDATA 'PC-Maintenance-Kit'
Assert-True ($settingsPath.StartsWith($appDataPrefix)) 'GUI settings live under LocalAppData'

Assert-True ($Script:AppVersion -eq '5.1.6') 'AppVersion is 5.1.6'

Apply-ModeFlags Full
Assert-True ($Script:DoWinUpdate -eq $false) 'Weekly Full leaves Windows Update off'
Assert-True ($Script:DoWinget -eq $false) 'Weekly Full leaves winget off'
Assert-True ($Script:DoCleanup -eq $true) 'Weekly Full runs cleanup'
Reset-MaintenanceFlags

. (Join-Path $Root 'lib\Gaming.ps1')
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
