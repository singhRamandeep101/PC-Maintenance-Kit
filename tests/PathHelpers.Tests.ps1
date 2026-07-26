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

if ($failed -gt 0) {
    Write-Host "`n$failed test(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll path helper tests passed." -ForegroundColor Green
exit 0
