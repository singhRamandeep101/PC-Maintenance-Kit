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

function Invoke-GuiLayoutHunts {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    . (Join-Path $Root 'lib\Gaming.ps1')
    . (Join-Path $Root 'lib\Device.ps1')
    . (Join-Path $Root 'lib\Security.ps1')
    . (Join-Path $Root 'lib\Score.ps1')
    . (Join-Path $Root 'lib\Care.ps1')
    . (Join-Path $Root 'lib\Gui.ps1')
    $Script:Theme = Get-GuiTheme
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(-4000, -4000)
    $form.ClientSize = New-Object System.Drawing.Size(1000, 860)
    $form.ShowInTaskbar = $false
    $pages = @{}
    foreach ($name in @('Home','Cleanup','Updates','Gaming','Repair','Security','Device')) {
        $page = New-Object System.Windows.Forms.Panel
        $page.Dock = 'Fill'
        $form.Controls.Add($page)
        $pages[$name] = $page
    }
    $homePage = Add-GuiHomePage -Page $pages.Home -Theme $Script:Theme
    $clean = Add-GuiCleanupPage -Page $pages.Cleanup -Theme $Script:Theme
    $upd = Add-GuiUpdatesPage -Page $pages.Updates -Theme $Script:Theme
    $game = Add-GuiGamingPage -Page $pages.Gaming -Theme $Script:Theme
    $repair = Add-GuiRepairPage -Page $pages.Repair -Theme $Script:Theme
    $security = Add-GuiSecurityPage -Page $pages.Security -Theme $Script:Theme
    $device = Add-GuiDevicePage -Page $pages.Device -Theme $Script:Theme
    foreach ($k in @('BtnWeekly','ChkHomeWU','ChkScheduleWeekly','ChkScheduleUpdates','ChkScheduleGaming','LblLastScheduledRun','HomeFixesVal','HomeSecurityVal','CpuMain')) {
        Assert-True ($homePage.Contains($k) -and $null -ne $homePage[$k]) "Home returns $k"
    }
    Assert-True (-not $homePage.ChkScheduleUpdates.Checked) 'Weekly task update opt-in defaults off'
    foreach ($k in @('BtnCleanup','BtnPreview','DaysNum','LblCleanupLive','ChkWuCache')) {
        Assert-True ($clean.Contains($k) -and $null -ne $clean[$k]) "Cleanup returns $k"
    }
    foreach ($k in @('BtnUpdates','ChkUpdWU','ChkUpdWinget','LblUpdatesLive')) {
        Assert-True ($upd.Contains($k) -and $null -ne $upd[$k]) "Updates returns $k"
    }
    foreach ($k in @('BtnGamingOpt','OptFixesVal','OptGradeLetter','OptStatusPill','GameStartupVal','BtnOpenStartup')) {
        Assert-True ($game.Contains($k) -and $null -ne $game[$k]) "Gaming returns $k"
    }
    foreach ($k in @('BtnRepair','ChkRepRestore','LblRepairLive')) {
        Assert-True ($repair.Contains($k) -and $null -ne $repair[$k]) "Repair returns $k"
    }
    foreach ($k in @('BtnOpenMalwarebytes','BtnOpenWindowsSecurity','BtnRefreshSecurity','SecVerdict','SecRealtime')) {
        Assert-True ($security.Contains($k) -and $null -ne $security[$k]) "Security returns $k"
    }
    Assert-True ($security.SecVerdict.Text -eq 'Reading...') 'Security page shows Reading before the first probe'
    Assert-True ($security.BtnOpenWindowsSecurity.Text -eq 'Open Windows Security') 'Security page button opens Windows Security'
    foreach ($k in @('BtnRestartNow','DevCpu','DevRamTip','DevRebootPill')) {
        Assert-True ($device.Contains($k) -and $null -ne $device[$k]) "Device returns $k"
    }
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $fixes = $homePage.HomeFixesVal
    $fixes.Text = "1. Startup apps - 14 apps at sign-in`r`n2. GPU driver - two versions behind`r`n3. Memory - single channel holds 1% lows back"
    [System.Windows.Forms.Application]::DoEvents()
    $card = $fixes.Parent
    $fits = ($fixes.Bottom + $fixes.Margin.Bottom) -le ($card.ClientSize.Height + 8)
    Assert-True ($fits -and $fixes.Width -gt 40) 'Home top fixes stay inside the card'
    $tip = $device.DevRamTip
    $tip.Text = 'You have 1 stick (CMK32GX5M1B5600C36). Buy a matching second stick of the same model for dual-channel. Search: CMK32GX5M1B5600C36.'
    [System.Windows.Forms.Application]::DoEvents()
    $tipCard = $tip.Parent
    $tipFits = ($tip.Bottom + $tip.Margin.Bottom) -le ($tipCard.ClientSize.Height + 8)
    Assert-True ($tipFits -and $tip.Width -gt 40) 'Device RAM tip stays inside the card'
    Assert-True ($repair.BtnRepair.BackColor.ToArgb() -eq $Script:Theme.Danger.ToArgb()) 'DISM button stays the danger color'
    Assert-True ($device.BtnRestartNow.ForeColor.ToArgb() -eq [System.Drawing.Color]::FromArgb(248, 113, 113).ToArgb()) 'Restart text stays red'
    $form.Close()
    $form.Dispose()
}

if ($env:PCMK_GUI_HUNT -eq '1') {
    Invoke-GuiLayoutHunts
    if ($failed -gt 0) { exit 1 }
    Write-Host 'GUI layout hunts passed.' -ForegroundColor Green
    exit 0
}

$versionFile = Join-Path $Root 'VERSION'
Assert-True (Test-Path -LiteralPath $versionFile) 'VERSION file exists'
$fileVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
Assert-True ($Script:AppVersion -eq $fileVersion) ("AppVersion matches VERSION ($fileVersion)")

Assert-True ($null -eq (Join-PathSafe $null 'a')) 'Join-PathSafe null base -> null'
Assert-True ($null -eq (Join-PathSafe '' 'a')) 'Join-PathSafe empty base -> null'
$joined = Join-PathSafe 'C:\Steam' 'steamapps\downloading'
Assert-True ($joined -eq 'C:\Steam\steamapps\downloading' -or $joined -eq 'C:\Steam/steamapps/downloading') 'Join-PathSafe combines'
$driveJoined = Join-PathSafe ($env:SystemDrive.TrimEnd('\')) 'Users'
Assert-True ($driveJoined -eq (($env:SystemDrive.TrimEnd('\')) + '\Users')) 'Join-PathSafe bare drive is not drive-relative'

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
Assert-True (-not (Test-SafeCleanupPath (Join-Path $env:SystemRoot 'System32\drivers'))) 'Unsafe: under System32'
Assert-True (-not (Test-SafeCleanupPath (Join-Path $env:USERPROFILE 'Documents\Games'))) 'Unsafe: under Documents'
Assert-True (-not (Test-SafeCleanupPath (Join-Path $env:SystemRoot 'Logs'))) 'Unsafe: other Windows folder'
Assert-True (Test-SafeCleanupPath (Get-WindowsUpdateDownloadPath)) 'Safe: WU download cache'
$otherUser = Join-Path (Join-Path $env:SystemDrive '\Users') 'pcmk-not-me\Desktop'
Assert-True (-not (Test-SafeCleanupPath $otherUser)) 'Unsafe: another user profile'

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

$measureRoot = Join-Path $env:TEMP ('pcmk-measure-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$measureOut = Join-Path $env:TEMP ('pcmk-measure-out-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $measureRoot -Force | Out-Null
New-Item -ItemType Directory -Path $measureOut -Force | Out-Null
$measureOld = Join-Path $measureRoot 'old.bin'
$measureNew = Join-Path $measureRoot 'new.bin'
$measureSecret = Join-Path $measureOut 'secret.bin'
[System.IO.File]::WriteAllBytes($measureOld, (New-Object byte[] 100))
[System.IO.File]::WriteAllBytes($measureNew, (New-Object byte[] 40))
[System.IO.File]::WriteAllBytes($measureSecret, (New-Object byte[] 20))
(Get-Item -LiteralPath $measureOld).LastWriteTime = (Get-Date).AddDays(-10)
$measureAll = Measure-ContainedTreeBytes -Root $measureRoot -OlderThanDays 0
$measureAged = Measure-ContainedTreeBytes -Root $measureRoot -OlderThanDays 2
Assert-True ($measureAll -eq 140) 'Preview size counts every file in the folder'
Assert-True ($measureAged -eq 100) 'Preview size skips files newer than the cutoff'
$measureLink = Join-Path $measureRoot 'link'
cmd /c "mklink /J `"$measureLink`" `"$measureOut`"" | Out-Null
if (Test-Path -LiteralPath (Join-Path $measureLink 'secret.bin')) {
    $measureLinked = Measure-ContainedTreeBytes -Root $measureRoot -OlderThanDays 0
    Assert-True ($measureLinked -eq 140) 'Preview size does not follow a junction'
    cmd /c "rmdir `"$measureLink`"" | Out-Null
} else {
    Assert-True $false 'Could not create a junction for the preview size test'
}
Remove-Item -LiteralPath $measureRoot -Recurse -Force -EA SilentlyContinue
Remove-Item -LiteralPath $measureOut -Recurse -Force -EA SilentlyContinue

# A junction inside an approved folder must not let the delete escape
$jRoot = Join-Path $env:TEMP ('pcmk-junc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$outside = Join-Path $env:TEMP ('pcmk-secret-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $jRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outside -Force | Out-Null
$secret = Join-Path $outside 'secret.txt'
Set-Content -LiteralPath $secret -Value 'keep' -Encoding ASCII
$inside = Join-Path $jRoot 'inside.txt'
Set-Content -LiteralPath $inside -Value 'gone' -Encoding ASCII
$link = Join-Path $jRoot 'link'
cmd /c "mklink /J `"$link`" `"$outside`"" | Out-Null
$secretViaLink = Join-Path $link 'secret.txt'
if (Test-Path -LiteralPath $secretViaLink) {
    $null = Remove-OldFilesInPath -Path $jRoot -OlderThanDays 0 -DeleteFoldersToo
    Assert-True (Test-Path -LiteralPath $secret) 'Cleanup does not follow a junction out of the root'
    Assert-True (-not (Test-Path -LiteralPath $inside)) 'Cleanup still deletes real files beside a junction'
    Assert-True (Test-Path -LiteralPath $link) 'Cleanup leaves the junction itself in place'
} else {
    Assert-True $false 'Could not create a junction for the containment test'
}
cmd /c "rmdir `"$link`"" | Out-Null
Remove-Item -LiteralPath $jRoot -Recurse -Force -EA SilentlyContinue
Remove-Item -LiteralPath $outside -Recurse -Force -EA SilentlyContinue

$settings = Get-DefaultGuiSettings
Assert-True ($settings.HomeWU -eq $false) 'Default HomeWU is false'
Assert-True ($settings.HomeWinget -eq $false) 'Default HomeWinget is false'
Assert-True ($settings.ScheduleUpdates -eq $false) 'Default ScheduleUpdates is false'
Assert-True ($settings.ScheduleGaming -eq $false) 'Default ScheduleGaming is false'
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
function Test-SamePath([string]$Left, [string]$Right) {
    if (-not $Left -or -not $Right) { return $false }
    return ([System.IO.Path]::GetFullPath($Left).TrimEnd('\') -eq [System.IO.Path]::GetFullPath($Right).TrimEnd('\'))
}
$hasShader = @($chromPaths | Where-Object { Test-SamePath $_ (Join-Path $fakeUd 'ShaderCache') }).Count -gt 0
$hasGuest = @($chromPaths | Where-Object { Test-SamePath $_ (Join-Path $fakeUd 'Guest Profile\Cache') }).Count -gt 0
Assert-True $hasShader 'Chromium root ShaderCache included'
Assert-True $hasGuest 'Guest Profile Cache included'
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
Assert-True ($null -eq (Compare-AppVersion -Current '5.3.0' -Other 'not-a-version')) 'Compare-AppVersion returns null on garbage input'
$kitZip = Select-KitReleaseZip -Assets @(
    [pscustomobject]@{ name = 'notes.zip'; browser_download_url = 'https://example.invalid/notes.zip' }
    [pscustomobject]@{ name = 'PC-Maintenance-Kit-v9.9.9.zip'; browser_download_url = 'https://example.invalid/kit.zip' }
)
Assert-True ($kitZip.name -eq 'PC-Maintenance-Kit-v9.9.9.zip') 'Release picker prefers the kit zip'
$kitSum = Select-KitReleaseChecksum -Assets @(
    [pscustomobject]@{ name = 'other.zip.sha256'; browser_download_url = 'https://example.invalid/other' }
    [pscustomobject]@{ name = 'PC-Maintenance-Kit-v9.9.9.zip.sha256'; browser_download_url = 'https://example.invalid/kit' }
) -ZipName 'PC-Maintenance-Kit-v9.9.9.zip'
Assert-True ($kitSum.name -eq 'PC-Maintenance-Kit-v9.9.9.zip.sha256') 'Checksum picker matches the kit zip name'
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

$planProbe = Join-Path $env:TEMP ('pcmk-plan-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
function Get-PreviousPowerPlanPath { $planProbe }
Save-PreviousPowerPlan -Guid '11111111-1111-1111-1111-111111111111'
Save-PreviousPowerPlan -Guid '22222222-2222-2222-2222-222222222222'
$savedPlan = (Get-Content -LiteralPath $planProbe -Raw).Trim()
Assert-True ($savedPlan -eq '11111111-1111-1111-1111-111111111111') 'Previous power plan is saved once and not overwritten'
Remove-Item -LiteralPath $planProbe -Force -EA SilentlyContinue
function Get-PreviousPowerPlanPath {
    $dir = Join-Path $env:LOCALAPPDATA 'PC-Maintenance-Kit'
    return (Join-Path $dir 'previous-power-plan.txt')
}

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

. (Join-Path $Root 'lib\Security.ps1')
$securityErr = $null
$securityHealth = $null
try {
    $securityHealth = Get-SecurityHealth
} catch {
    $securityErr = $_
}
Assert-True ($null -eq $securityErr) 'Get-SecurityHealth does not throw'
Assert-True ($null -ne $securityHealth) 'Get-SecurityHealth returns an object'
foreach ($prop in @('Defender','Firewall','Malwarebytes','Verdict')) {
    Assert-True ($securityHealth.PSObject.Properties.Name -contains $prop) "Get-SecurityHealth returns $prop"
}
Assert-True ($securityHealth.Verdict -eq 'Protected' -or $securityHealth.Verdict -eq 'Needs attention') 'Security verdict is Protected or Needs attention'
Assert-True ($securityHealth.Malwarebytes.Installed -is [bool]) 'Malwarebytes.Installed is bool'
$securityHealth2 = Get-SecurityHealth
Assert-True ([object]::ReferenceEquals($securityHealth, $securityHealth2)) 'Get-SecurityHealth cache returns same object'
$securityText = Format-SecurityHealthText
Assert-True ($securityText -match 'Scans run in Windows Security or Malwarebytes') 'Security report says scans stay in the other apps'
$securityRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Security.ps1') -Raw
Assert-True ($securityRaw -notmatch 'Start-MpScan') 'Security health does not start a Defender scan'

$mbRoot = Join-Path $env:TEMP ('pcmk-mb-' + [guid]::NewGuid().ToString('N'))
$mbExeDir = Join-Path $mbRoot 'Malwarebytes\Anti-Malware'
$mbExe = Join-Path $mbExeDir 'Malwarebytes.exe'
$mbMissing = Join-Path $env:TEMP ('pcmk-mb-missing-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $mbExeDir -Force | Out-Null
    Set-Content -LiteralPath $mbExe -Value 'not a real executable' -Encoding ASCII
    $mbFound = Find-MalwarebytesInstall -SearchRoots @($mbRoot)
    Assert-True ($mbFound.Installed) 'Fake Malwarebytes.exe is detected'
    # CI's TEMP can be a short 8.3 path. Resolve-Path keeps that form;
    # Get-Item.FullName expands both sides to the same long path.
    $mbFoundPath = (Get-Item -LiteralPath $mbFound.Path).FullName
    $mbPlantedPath = (Get-Item -LiteralPath $mbExe).FullName
    Assert-True ($mbFoundPath -eq $mbPlantedPath) 'Fake Malwarebytes path is the planted exe'
    $mbAbsent = Find-MalwarebytesInstall -SearchRoots @($mbMissing)
    Assert-True (-not $mbAbsent.Installed) 'Search root with no Malwarebytes.exe is not installed'
} finally {
    Remove-Item -LiteralPath $mbRoot -Recurse -Force -EA SilentlyContinue
}

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
$cap = Get-SystemDriveCapacityGB
$cap2 = Get-SystemDriveCapacityGB
Assert-True ($null -eq $cap -or $cap -gt 0) 'Drive capacity comes from the shared C: read'
Assert-True ($cap -eq $cap2) 'Drive capacity cache is stable'
$uniqueTemps = @(Select-UniqueCleanupPaths -Paths @($env:TEMP, "$env:LOCALAPPDATA\Temp", $env:TEMP))
$uniqueKeys = @($uniqueTemps | ForEach-Object { [string]$_.ToLowerInvariant() } | Select-Object -Unique)
Assert-True ($uniqueKeys.Count -eq @($uniqueTemps).Count) 'Cleanup path list drops duplicate folders'
$tempFull = ''
$localTemp = ''
try { $tempFull = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\').ToLowerInvariant() } catch { }
try { $localTemp = [System.IO.Path]::GetFullPath("$env:LOCALAPPDATA\Temp").TrimEnd('\').ToLowerInvariant() } catch { }
if ($tempFull -and $tempFull -eq $localTemp) {
    Assert-True (@($uniqueKeys | Where-Object { $_ -eq $tempFull }).Count -eq 1) 'TEMP and LocalAppData Temp are measured once'
}
$prot1 = Get-ProtectedCleanupPaths
$prot2 = Get-ProtectedCleanupPaths
Assert-True ([object]::ReferenceEquals($prot1, $prot2)) 'Get-ProtectedCleanupPaths caches the protected list'

. (Join-Path $Root 'lib\Score.ps1')
$ssdScore = Get-DiskMediaScore -MediaType 'SSD' -FriendlyName 'Disk' -MaxPoints 40
$unspecScore = Get-DiskMediaScore -MediaType 'Unspecified' -FriendlyName 'Disk' -MaxPoints 40
$hddScore = Get-DiskMediaScore -MediaType 'HDD' -FriendlyName 'Disk' -MaxPoints 40
Assert-True ($ssdScore.Status -eq 'Good' -and $ssdScore.Points -eq 40) 'SSD media scores full points'
Assert-True ($unspecScore.Status -eq 'Unknown' -and $unspecScore.Points -eq 0) 'Unspecified media does not score as an SSD'
Assert-True ($hddScore.Status -eq 'Bad' -and $hddScore.Points -eq 0) 'HDD media scores zero'
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
$byName = @{}
foreach ($c in @($optScore.Categories)) { $byName[$c.Name] = [double]$c.Weight }
$actionable = $byName.Power + $byName.GamingFeatures + $byName.Background + $byName.Hygiene + $byName.Security
$hardware = $byName.Storage + $byName.Memory
Assert-True ($actionable -gt $hardware) 'Settings you can change outweigh disk type and RAM'
$secCat = @($optScore.Categories | Where-Object { $_.Name -eq 'Security' } | Select-Object -First 1)
Assert-True ($null -ne $secCat -and [math]::Abs($secCat.Weight - 0.10) -lt 0.001) 'Score includes a Security category'
$scanCheck = @($optScore.Checks | Where-Object { $_.Id -eq 'security_scan' } | Select-Object -First 1)
Assert-True ($null -ne $scanCheck) 'Score includes the security scan check'
$freshScan = Get-SecurityScanFreshness -LastScan ([datetime]::Now.AddDays(-3)) -Known $true
$edgeScan = Get-SecurityScanFreshness -LastScan ([datetime]::Now.AddDays(-20)) -Known $true
$staleScan = Get-SecurityScanFreshness -LastScan ([datetime]::Now.AddDays(-21)) -Known $true
$neverScan = Get-SecurityScanFreshness -LastScan $null -Known $true
$unreadScan = Get-SecurityScanFreshness -LastScan $null -Known $false
Assert-True ($freshScan.Status -eq 'Good' -and $freshScan.Points -eq 100) 'A scan 3 days ago keeps full points'
Assert-True ($edgeScan.Status -eq 'Good' -and $edgeScan.Points -eq 100) 'A scan 20 days ago keeps full points'
Assert-True ($staleScan.Status -eq 'Bad' -and $staleScan.Points -eq 0) 'A scan 21 days ago scores zero'
Assert-True ($neverScan.Status -eq 'Bad' -and $neverScan.Points -eq 0) 'No scan on record scores zero'
Assert-True ($unreadScan.Status -eq 'Unknown' -and $unreadScan.Points -eq 100) 'An unreadable scan time does not lower the score'
$hygCat = @($optScore.Categories | Where-Object { $_.Name -eq 'Hygiene' } | Select-Object -First 1)
Assert-True ($null -ne $hygCat) 'Score includes Hygiene category'
if (-not $hardAny) {
    Assert-True ($hygCat.Score -eq 100) 'Hygiene is 100 when no hard reboot signal'
    $rebootCheck = @($optScore.Checks | Where-Object { $_.Id -eq 'reboot_pending' } | Select-Object -First 1)
    Assert-True ($null -ne $rebootCheck -and $rebootCheck.Status -eq 'Good') 'reboot_pending is Good without hard reboot signal'
}
$hagsCheck = @($optScore.Checks | Where-Object { $_.Id -eq 'hags' } | Select-Object -First 1)
Assert-True ($null -ne $hagsCheck -and $hagsCheck.Points -eq $hagsCheck.Max) 'HAGS does not soft-cap points when off/unknown'
Assert-True (Test-StartupApprovedEnabled $null) 'Missing startup approval means the app still starts'
Assert-True (Test-StartupApprovedEnabled ([byte[]](2, 0, 0, 0))) 'StartupApproved byte 2 means on'
Assert-True (-not (Test-StartupApprovedEnabled ([byte[]](3, 0, 0, 0)))) 'StartupApproved byte 3 means off'
$startupApps = @(Get-StartupApps)
Assert-True ($null -ne $startupApps) 'Get-StartupApps returns a collection'
Assert-True ((Get-StartupEntryCount) -eq @($startupApps | Where-Object { $_.Enabled }).Count) 'Startup count matches enabled apps'
$startupText = Format-StartupAppList $startupApps
Assert-True ($startupText -match 'Windows') 'Startup list tells you what starts with Windows'
$startupMerged = @(Select-StartupAppWinners @(
    [pscustomobject]@{ Name = 'Steam'; Enabled = $false; Source = 'User' },
    [pscustomobject]@{ Name = 'steam'; Enabled = $true; Source = 'User folder' }
))
Assert-True ($startupMerged.Count -eq 1 -and $startupMerged[0].Enabled) 'Enabled startup entry wins over a disabled one with the same name'
Assert-True (-not (Test-DefenderThreatActive 'False')) 'Threat IsActive string False is not active'
Assert-True (-not (Test-DefenderThreatActive $false)) 'Threat IsActive false is not active'
Assert-True (Test-DefenderThreatActive $true) 'Threat IsActive true is active'
$sigToday = Format-SignatureHealthText ([pscustomobject]@{ Signatures = 'Current'; SignatureAgeDays = 0 })
Assert-True ($sigToday -eq 'Current (today)') 'Signature age of 0 days says today'
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
$validActions = @('GamingOptimize', 'OpenStorage', 'CopyRamTip', 'OpenStartup', 'OpenServices', 'OpenTasks', 'OpenDisplay', 'OpenSecurity', 'None')
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
Assert-True ($optScore.BiggestLimiter -eq (Get-BiggestScoreLimiter $optScore.Categories)) 'BiggestLimiter is the category that costs the most points'
$limiterProbe = @(
    [pscustomobject]@{ Name = 'Hygiene'; Score = 30; Weight = 0.05 },
    [pscustomobject]@{ Name = 'Memory'; Score = 50; Weight = 0.09 }
)
Assert-True ((Get-BiggestScoreLimiter $limiterProbe) -eq 'Memory') 'Limiter prefers the larger point loss over the lower percent'
$holdApps = @(
    [pscustomobject]@{ Name = 'Riot Vanguard'; Enabled = $false; Source = 'Machine' },
    [pscustomobject]@{ Name = 'WallpaperEngine'; Enabled = $true; Source = 'User' }
)
$holdServices = @(
    [pscustomobject]@{ Name = 'vgc'; DisplayName = 'vgc'; PathName = '"C:\Program Files\Riot Vanguard\vgc.exe"' },
    [pscustomobject]@{ Name = 'wuauserv'; DisplayName = 'Windows Update'; PathName = 'C:\WINDOWS\system32\svchost.exe -k netsvcs' }
)
$holds = @(Select-StartupServiceHolds -Apps $holdApps -Services $holdServices)
Assert-True ($holds.Count -eq 1 -and $holds[0] -eq 'Riot Vanguard') 'A disabled startup app is listed when its service still starts'
$windowsHold = @(Select-StartupServiceHolds -Apps @([pscustomobject]@{ Name = 'WindowsUpdate'; Enabled = $false; Source = 'Machine' }) -Services @($holdServices[1]))
Assert-True ($windowsHold.Count -eq 0) 'A Windows service does not count as a startup hold'
$holdLine = Format-StartupServiceHoldList @('Riot Vanguard')
Assert-True ($holdLine -eq 'Still starts as a service: Riot Vanguard') 'Service hold text names the app'
$logonTasks = @(
    [pscustomobject]@{ Name = 'Steam Client'; Path = '\'; Enabled = $true; Logon = $true },
    [pscustomobject]@{ Name = 'WallpaperEngine'; Path = '\'; Enabled = $true; Logon = $true },
    [pscustomobject]@{ Name = 'Something'; Path = '\Microsoft\Windows\'; Enabled = $true; Logon = $true },
    [pscustomobject]@{ Name = 'PC Maintenance Kit - Weekly Full'; Path = '\'; Enabled = $true; Logon = $true }
)
$logonApps = @([pscustomobject]@{ Name = 'WallpaperEngine'; Enabled = $true; Source = 'User' })
$logonTasks += @(
    [pscustomobject]@{ Name = 'cua-driver-serve'; Path = '\'; Enabled = $true; Logon = $true },
    [pscustomobject]@{ Name = 'StartCN'; Path = '\'; Enabled = $true; Logon = $true },
    [pscustomobject]@{ Name = 'StartDVR'; Path = '\'; Enabled = $true; Logon = $true }
)
$logonNames = @(Select-ExtraLogonTaskNames -Tasks $logonTasks -Apps $logonApps -SkipName 'PC Maintenance Kit - Weekly Full')
Assert-True ($logonNames.Count -eq 1 -and $logonNames[0] -eq 'Steam Client') 'Sign-in list keeps readable app names and skips internal task ids'
Assert-True ((Format-LogonTaskList @('Steam Client')) -eq 'Also signs in: Steam Client') 'Sign-in list names the task'
Assert-True (Test-StartupServiceNameMatch -AppName 'Riot Vanguard' -ServiceName 'vgc' -DisplayName 'vgc' -PathName '"C:\Program Files\Riot Vanguard\vgc.exe"') 'Service match accepts the folder name'
Assert-True (-not (Test-StartupServiceNameMatch -AppName 'Edge' -ServiceName 'edgeupdate' -DisplayName 'edgeupdate' -PathName 'C:\Program Files\SomeEdgeHelper\tool.exe')) 'Service match does not treat a longer folder name as the app'
$plainStart = Get-StartupBackgroundJudgement -ReadOk $true -EnabledCount 1 -AppList '1 starts with Windows: WallpaperEngine' -HoldText '' -LogonText ''
Assert-True ($plainStart.Status -eq 'Good' -and $plainStart.Fix -eq 'None') 'One startup app with nothing else stays Good'
$logonStart = Get-StartupBackgroundJudgement -ReadOk $true -EnabledCount 1 -AppList '1 starts with Windows: WallpaperEngine' -HoldText '' -LogonText 'Also signs in: Steam Client'
Assert-True ($logonStart.Status -eq 'Warn' -and $logonStart.Fix -eq 'OpenStartup') 'An extra sign-in task warns and opens Startup apps'
Assert-True ($logonStart.Hint -match 'Startup apps' -and $logonStart.Hint -notmatch 'cua') 'The sign-in recommendation is a plain sentence'
$heldStart = Get-StartupBackgroundJudgement -ReadOk $true -EnabledCount 1 -AppList '1 starts with Windows: WallpaperEngine' -HoldText 'Still starts as a service: Riot Vanguard' -LogonText ''
Assert-True ($heldStart.Status -eq 'Warn' -and $heldStart.Fix -eq 'OpenServices') 'A service that still starts warns and opens Services'
Assert-True (Test-TrustedKitDownloadUrl 'https://github.com/singhRamandeep101/PC-Maintenance-Kit/releases/download/v5.5.0/kit.zip') 'GitHub release URL for this repo is trusted'
Assert-True (-not (Test-TrustedKitDownloadUrl 'https://objects.githubusercontent.com/github-production-release-asset/kit.zip')) 'A GitHub CDN address is not approved by itself'
Assert-True (-not (Test-TrustedKitDownloadUrl 'http://github.com/singhRamandeep101/PC-Maintenance-Kit/releases/download/v5.5.0/kit.zip')) 'Plain http download is refused'
Assert-True (-not (Test-TrustedKitDownloadUrl 'https://github.com/other/PC-Maintenance-Kit/releases/download/v5.5.0/kit.zip')) 'Another GitHub repo is refused'
Assert-True (-not (Test-TrustedKitDownloadUrl 'https://evil.example/kit.zip')) 'An unknown host is refused'
$zipDir = Join-Path $env:TEMP ('pcmk-zip-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $zipDir -Force | Out-Null
$safeZip = Join-Path $zipDir 'safe.zip'
$slipZip = Join-Path $zipDir 'slip.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$safeStream = [System.IO.File]::Open($safeZip, 'Create')
$safeArchive = New-Object System.IO.Compression.ZipArchive($safeStream, [System.IO.Compression.ZipArchiveMode]::Create)
[void]$safeArchive.CreateEntry('PC-Maintenance.ps1')
$safeArchive.Dispose()
$safeStream.Dispose()
$slipStream = [System.IO.File]::Open($slipZip, 'Create')
$slipArchive = New-Object System.IO.Compression.ZipArchive($slipStream, [System.IO.Compression.ZipArchiveMode]::Create)
[void]$slipArchive.CreateEntry('..\evil.ps1')
$slipArchive.Dispose()
$slipStream.Dispose()
Assert-True (Test-ZipEntriesSafe -ZipPath $safeZip -Destination (Join-Path $zipDir 'out')) 'A normal ZIP entry is safe to extract'
Assert-True (-not (Test-ZipEntriesSafe -ZipPath $slipZip -Destination (Join-Path $zipDir 'out'))) 'A ZIP entry that escapes the folder is refused'
Remove-Item -LiteralPath $zipDir -Recurse -Force -EA SilentlyContinue
$staleHeadline = Get-DisplayedOptimizationScore -WeightedScore 90 -ScanStatus 'Bad'
Assert-True ($staleHeadline.Score -eq 69 -and $staleHeadline.Weighted -eq 90) 'A stale scan holds a 90 at Needs work and keeps the weighted total'
Assert-True ((Get-OptimizationGrade $staleHeadline.Score) -eq 'Needs work') 'A stale scan headline grade is Needs work'
Assert-True ($staleHeadline.Note -match '20 days') 'A stale scan explains the hold'
$freshHeadline = Get-DisplayedOptimizationScore -WeightedScore 90 -ScanStatus 'Good'
Assert-True ($freshHeadline.Score -eq 90 -and [string]::IsNullOrEmpty($freshHeadline.Note)) 'A recent scan leaves the weighted score alone'
$unknownHeadline = Get-DisplayedOptimizationScore -WeightedScore 90 -ScanStatus 'Unknown'
Assert-True ($unknownHeadline.Score -eq 90) 'An unreadable scan does not hold the headline'
$lowHeadline = Get-DisplayedOptimizationScore -WeightedScore 40 -ScanStatus 'Bad'
Assert-True ($lowHeadline.Score -eq 40) 'A score already under Needs work is not raised'

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
Assert-True ($getRaw -match 'function Test-TrustedKitDownloadUrl') 'Get.ps1 checks the download address'
Assert-True ($getRaw -match 'Refusing to download from an unexpected address') 'Get.ps1 refuses an unexpected download address'
Assert-True ($getRaw -match 'function Test-ZipEntriesSafe') 'Get.ps1 checks ZIP entries'
Assert-True ($getRaw -match 'escapes the folder') 'Get.ps1 refuses a ZIP entry that escapes the folder'
Assert-True ($getRaw -match 'Refusing to install without integrity') 'Get.ps1 fails closed without SHA256'
Assert-True ($getRaw -notmatch 'refs/heads/main\.zip') 'Get.ps1 no longer falls back to main.zip'
Assert-True ($getRaw -match 'Could not fetch GitHub release info') 'Get.ps1 surfaces network/API errors'
Assert-True ($getRaw -match 'zip\.digest') 'Get.ps1 can fall back to asset digest'
Assert-True ($getRaw -match 'PC-Maintenance-Kit-v') 'Get.ps1 prefers the named kit zip'
Assert-True ($getRaw -match 'Test-PayloadHealthy') 'Get.ps1 health-checks the payload'
Assert-True ($getRaw -match 'Authenticode status') 'Get.ps1 requires a present signature to be Valid'
Assert-True ($getRaw -match 'PC-Maintenance-Kit-backup') 'Get.ps1 backs up an existing install'
$coreRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Core.ps1') -Raw
Assert-True ($coreRaw -match 'upgrade --all --source winget --silent') 'Core.ps1 uses fast bulk winget upgrade'
Assert-True ($coreRaw -match 'upgrade --id \$id --exact --source winget --silent') 'Core.ps1 direct-upgrades explicit-targeting packages silently'
Assert-True ($coreRaw -match 'function ConvertFrom-WingetUpgradeList') 'Core.ps1 splits winget list sections'
Assert-True ($coreRaw -match 'MSFT_Partition') 'System disk is read without the Storage module first'
Assert-True ($coreRaw -match 'pin add --id') 'Core.ps1 pins skip-list before bulk upgrade'
Assert-True ($coreRaw -notmatch 'function Invoke-WingetPerIdUpgrade') 'Core.ps1 does not upgrade winget packages one by one'

$wingetSample = @"
No newer package versions are available from the configured sources.
Name                             Id                          Version     Available   Source
-------------------------------------------------------------------------------------------
Unity Hub                        Unity.UnityHub              3.4.1       3.8.0       winget
1 package(s) have version numbers that cannot be determined.
Name                             Id                          Version
--------------------------------------------------------------------
Roblox Player                    Roblox.Roblox               Unknown
The following packages require explicit targeting for upgrade:
Name                             Id                          Version     Available   Source
-------------------------------------------------------------------------------------------
Unity Editor 2022.3.62f1         Unity.Unity.2022            2022.3.20   2022.3.62   winget
2 upgrades available.
"@
$wingetParsed = ConvertFrom-WingetUpgradeList -Text $wingetSample
Assert-True (@($wingetParsed.Bulk) -contains 'Unity.UnityHub') 'Bulk section keeps Unity Hub'
Assert-True (@($wingetParsed.Explicit) -contains 'Unity.Unity.2022') 'Explicit section keeps the Unity editor'
Assert-True (@($wingetParsed.Unknown) -contains 'Roblox.Roblox') 'Unknown-version section keeps Roblox'
Assert-True (@($wingetParsed.Bulk) -notcontains 'Unity.Unity.2022') 'Explicit id is not treated as a bulk upgrade'
$hubRow = @($wingetParsed.Rows | Where-Object { $_.Id -eq 'Unity.UnityHub' }) | Select-Object -First 1
Assert-True ($hubRow.Name -eq 'Unity Hub') 'Bulk row keeps the app name'
Assert-True ($hubRow.Version -eq '3.4.1') 'Bulk row keeps the installed version'
Assert-True ($hubRow.Available -eq '3.8.0') 'Bulk row keeps the available version'
Assert-True ($hubRow.Section -eq 'bulk') 'Bulk row section is bulk'
$editorRow = @($wingetParsed.Rows | Where-Object { $_.Id -eq 'Unity.Unity.2022' }) | Select-Object -First 1
Assert-True ($editorRow.Name -eq 'Unity Editor 2022.3.62f1') 'Explicit row keeps the editor name'
Assert-True ($editorRow.Section -eq 'explicit') 'Explicit row section is explicit'
$wingetChoices = @(Get-WingetUpgradeChoices -Rows $wingetParsed.Rows -BulkIds $wingetParsed.Bulk -ExplicitIds $wingetParsed.Explicit)
Assert-True ($wingetChoices.Count -eq 2) 'Choices include bulk and explicit apps'
Assert-True ((Format-WingetUpgradeLabel $wingetChoices[0]) -match 'Unity Hub') 'Choice label includes the app name'
Assert-True ((Format-WingetUpgradeLabel $wingetChoices[1]) -match '\(direct\)') 'Explicit choice is marked direct'
$wingetSplit = Split-WingetUpgradeSelection -BulkIds @('Unity.UnityHub','Mozilla.Firefox') -ExplicitIds @('Unity.Unity.2022') -SelectedIds @('Mozilla.Firefox')
Assert-True (@($wingetSplit.Bulk) -contains 'Mozilla.Firefox') 'Selection keeps the checked bulk app'
Assert-True (@($wingetSplit.ExcludedBulk) -contains 'Unity.UnityHub') 'Selection holds back the unchecked bulk app'
Assert-True (@($wingetSplit.Explicit).Count -eq 0) 'Unchecked explicit app is not upgraded'
Assert-True ($coreRaw -match 'Show-WingetPackagePicker') 'Core.ps1 asks which winget apps to update'
Assert-True ($coreRaw -match 'CheckedListBox') 'Core.ps1 uses a checklist for winget apps'
Assert-True ($coreRaw -match 'ExcludedJoined') 'Unchecked winget apps are passed into the upgrade job'
Assert-True ((Get-WingetUpgradeOutcome -Text 'Successfully upgraded' -ExitCode 0) -eq 'Upgraded') 'Direct upgrade success is Upgraded'
Assert-True ((Get-WingetUpgradeOutcome -Text 'Installer failed with exit code 1' -ExitCode 1) -eq 'Failed') 'Direct upgrade failure is Failed'
Assert-True ((Get-WingetUpgradeOutcome -Text 'This package does not support silent install' -ExitCode 0) -eq 'NeedsInteraction') 'Silent-unsupported installer is NeedsInteraction'
Assert-True ((ConvertTo-DiskHealthName 0) -eq 'Healthy') 'Disk health 0 is Healthy'
Assert-True ((ConvertTo-DiskMediaName 4) -eq 'SSD') 'Disk media 4 is SSD'
Assert-True ((ConvertTo-DiskMediaName 0) -eq 'Unspecified') 'Disk media 0 is Unspecified'
Assert-True ((ConvertTo-DiskMediaName 'SSD') -eq 'SSD') 'Disk media name SSD stays SSD'
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
Assert-True ($guiRaw -match "return 'Space'") 'Cleanup and updates refresh free space without a hardware rescan'
$deviceRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Device.ps1') -Raw
Assert-True ($deviceRaw -notmatch 'Get-Volume') 'Device summary does not import the Storage module via Get-Volume'
Assert-True ($deviceRaw -notmatch 'Get-Partition') 'Device summary does not call Get-Partition'
$scoreRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Score.ps1') -Raw
Assert-True ($scoreRaw -notmatch 'Get-Volume') 'Drive capacity does not call Get-Volume'
Assert-True ($coreRaw -match 'function Clear-HardwareProbeCaches') 'Core exposes Clear-HardwareProbeCaches'
Assert-True ($coreRaw -match 'EnumerateFiles') 'Cleanup streams files via EnumerateFiles'
Assert-True ($coreRaw -match 'Invoke-ContainedTreeWalk') 'Cleanup walks without following reparse points'
Assert-True ($coreRaw -notmatch 'looksClean') 'DISM success is not inferred from the log'
Assert-True ($coreRaw -match 'left as-is') 'Stopped update services are left alone outside an update run'
Assert-True ($coreRaw -match 'LeaveRunning') 'DISM and SFC are marked to keep running on Stop'
Assert-True ($coreRaw -match 'Stop will not kill DISM') 'Stop explains that DISM is left running'
Assert-True ($coreRaw -notmatch '\.Kill\(') 'Stop does not kill tracked processes'
Assert-True ($coreRaw -match 'winget upgrade" -TimeoutSec 3600 -LeaveRunning') 'winget upgrade is left running on Stop'
Assert-True ($coreRaw -match 'Installing Windows Updates" -TimeoutSec 3600 -Sta -LeaveRunning') 'Windows Update install is left running on Stop'
Assert-True ($coreRaw -notmatch 'DISM cancelled') 'Stop no longer reports DISM as cancelled'
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
$schedOff = '{"HomeRestore":true,"HomeShader":true,"HomeGaming":true,"HomeWU":true,"HomeWinget":true,"ScheduleUpdates":false,"TempOlderDays":2}'
Set-Content -LiteralPath $settingsProbe -Value $schedOff -Encoding ASCII
Apply-ScheduledCareFlags
Assert-True ($Script:DoCleanup) 'Scheduled run still cleans'
Assert-True (-not $Script:DoWinUpdate) 'Scheduled run leaves Windows Update off unless ScheduleUpdates is on'
Assert-True (-not $Script:DoWinget) 'Scheduled run leaves winget off unless ScheduleUpdates is on'
Assert-True (-not $Script:DoShaderCleanup) 'Scheduled run leaves shader cleanup off unless ScheduleGaming is on'
Assert-True (-not $Script:DoGamingOptimize) 'Scheduled run leaves gaming settings off unless ScheduleGaming is on'
Assert-True (-not $Script:DoRepair) 'Scheduled run never repairs'
$schedOn = '{"HomeRestore":true,"HomeShader":true,"HomeGaming":true,"HomeWU":true,"HomeWinget":true,"ScheduleUpdates":true,"ScheduleGaming":true,"TempOlderDays":2}'
Set-Content -LiteralPath $settingsProbe -Value $schedOn -Encoding ASCII
Apply-ScheduledCareFlags
Assert-True ($Script:DoWinUpdate) 'Scheduled run installs Windows Update when ScheduleUpdates is on'
Assert-True ($Script:DoWinget) 'Scheduled run installs winget when ScheduleUpdates is on'
Assert-True ($Script:DoShaderCleanup) 'Scheduled run clears shaders when ScheduleGaming is on'
Assert-True ($Script:DoGamingOptimize) 'Scheduled run applies gaming settings when ScheduleGaming is on'
$careRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\Care.ps1') -Raw
Assert-True ($careRaw -match 'ExecutionPolicy RemoteSigned') 'Weekly task uses RemoteSigned'
Assert-True ($careRaw -match 'Unblock-File') 'Weekly task clears the download mark'

$pmRaw = Get-Content -LiteralPath (Join-Path $Root 'PC-Maintenance.ps1') -Raw
Assert-True ($pmRaw -match "ValidateSet\([^\)]*'Scheduled'") 'Entry script accepts -Mode Scheduled'
Assert-True ($pmRaw -match 'lib\\Care\.ps1') 'Entry script loads Care.ps1'
Assert-True ($pmRaw -match 'lib\\Security\.ps1') 'Entry script loads Security.ps1'
Assert-True ($pmRaw -match 'Apply-ScheduledCareFlags') 'Scheduled mode applies care flags'
Assert-True ($pmRaw -match 'HeadlessRun') 'Scheduled mode is marked headless'

$guiRaw2 = Get-Content -LiteralPath (Join-Path $Root 'lib\Gui.ps1') -Raw
Assert-True ($guiRaw2 -match 'Enable-GuiDpiAwareness') 'GUI enables DPI awareness'
Assert-True ($guiRaw2 -match 'AutoScaleMode]::Dpi') 'Form uses DPI autoscaling'
Assert-True ($guiRaw2 -match 'DeviceDpi') 'Minimum window size follows DPI'
Assert-True ($guiRaw2 -match 'UseVisualStyleBackColor = \$false') 'Checkboxes paint on the panel instead of the system background'
Assert-True ($guiRaw2 -match 'FromArgb\(165, 165, 197\)') 'Muted text is light enough to read on the cards'
Assert-True ($coreRaw -match 'FromArgb\(176, 190, 208\)') 'Log gray is light enough to read on the dark log'
Assert-True ($guiRaw2 -match 'GuiPages\.ps1') 'GUI loads GuiPages module'
Assert-True ($guiRaw2 -match 'BtnPresetGamer') 'GUI wires care presets'
Assert-True ($guiRaw2 -match 'Unknown option. Nothing was run') 'CLI rejects an unknown menu choice'
Assert-True ($guiRaw2 -match 'BtnRestorePower') 'GUI can restore the previous power plan'
Assert-True ($guiRaw2 -match 'function Update-GuiPageOnVisit') 'Opening a tab can refresh a stale page'
Assert-True ($guiRaw2 -match 'Set-ActiveNav \(\[string\]\$sender\.Text\) -FromUser') 'Nav clicks are the visits that refresh'
Assert-True ($extrasRaw -notmatch 'EpicGamesLauncher\\Saved\\Data') 'Epic cleanup does not wipe Saved\Data'
Assert-True ($coreRaw -notmatch 'Microsoft\\Windows\\INetCache') 'Temp cleanup leaves Windows Internet cache alone'
Assert-True ($coreRaw -notmatch 'Microsoft\\Windows\\WebCache') 'Temp cleanup leaves the WebCache database alone'
Assert-True ($extrasRaw -notmatch 'Microsoft\\Windows\\INetCache') 'Cleanup preview leaves Windows Internet cache alone'
Assert-True ($extrasRaw -notmatch 'Microsoft\\Windows\\WebCache') 'Cleanup preview leaves the WebCache database alone'

$pagesRaw = Get-Content -LiteralPath (Join-Path $Root 'lib\GuiPages.ps1') -Raw
Assert-True ($pagesRaw -match 'function Add-GuiHomePage') 'GuiPages has Home builder'
Assert-True ($pagesRaw -match 'function Add-GuiGamingPage') 'GuiPages has Gaming builder'
Assert-True ($pagesRaw -match 'function Add-GuiSecurityPage') 'GuiPages has Security builder'
Assert-True ($pagesRaw -match 'ChkScheduleWeekly') 'Home page has schedule checkbox'
Assert-True ($pagesRaw -match 'GetNewClosure') 'GuiPages Resize handlers capture locals with GetNewClosure'
Assert-True ($pagesRaw -notmatch 'Anchor = "Top,Left,Right"') 'Pages do not anchor controls that a resize handler also sizes'
Assert-True ($pagesRaw -notmatch '\[math\]::Max\(200,') 'Resize does not force a control wider than its card'

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

$apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
if ($apartment -eq 'STA') {
    Invoke-GuiLayoutHunts
} else {
    $prevHunt = $env:PCMK_GUI_HUNT
    $env:PCMK_GUI_HUNT = '1'
    & powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    if ($LASTEXITCODE -ne 0) { $script:failed++ }
    if ($null -eq $prevHunt) { Remove-Item Env:PCMK_GUI_HUNT -ErrorAction SilentlyContinue } else { $env:PCMK_GUI_HUNT = $prevHunt }
}

if ($failed -gt 0) {
    Write-Host "`n$failed test(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll path helper tests passed." -ForegroundColor Green
exit 0
