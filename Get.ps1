#Requires -Version 5.1
<#
.SYNOPSIS
    Download, verify, and launch PC Maintenance Kit.

.DESCRIPTION
    Installs the latest GitHub *release* ZIP to %LOCALAPPDATA%\PC-Maintenance-Kit
    after checking its SHA256 checksum. Refuses to install without a verified hash.
    Administrator permission is requested on launch.

.EXAMPLE
    irm https://raw.githubusercontent.com/singhRamandeep101/PC-Maintenance-Kit/v5.6.0/Get.ps1 | iex

.NOTES
    The ZIP this script downloads is checked against its SHA256 before anything is installed.
    The script itself is the one piece that runs before that check. Prefer the tagged URL
    above, which does not move after the release, and read this file before piping it to iex.
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'singhRamandeep101/PC-Maintenance-Kit'
$Dest = Join-Path $env:LOCALAPPDATA 'PC-Maintenance-Kit'
$Work = Join-Path $env:TEMP ('PCMK-get-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$Headers = @{
    'User-Agent' = 'PC-Maintenance-Kit'
    Accept       = 'application/vnd.github+json'
}

function Get-ExpectedSha256 {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $line = (($Text -split "`r?`n") | Where-Object { $_ -and ($_ -notmatch '^\s*#') } | Select-Object -First 1)
    if ($line -match '([A-Fa-f0-9]{64})') { return $Matches[1].ToLowerInvariant() }
    return $null
}

function Test-Sha256File {
    param([string]$Path, [string]$Expected)
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $want = ($Expected -replace '\s', '').ToLowerInvariant()
    if ($actual -ne $want) {
        throw ("SHA256 mismatch.`n  expected: {0}`n  actual:   {1}" -f $want, $actual)
    }
    return $actual
}

function Test-TrustedKitDownloadUrl([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    $uri = $null
    try { $uri = [Uri]$Url } catch { return $false }
    if ($uri.Scheme -ne 'https') { return $false }
    $hostName = $uri.Host.ToLowerInvariant()
    # GitHub's download CDN is not accepted here. The release URL on github.com
    # is what we approve; the client may follow GitHub's own redirect after that.
    $repoHosts = @('github.com', 'api.github.com', 'codeload.github.com')
    $known = $false
    foreach ($name in $repoHosts) {
        if ($hostName -eq $name) { $known = $true; break }
    }
    if (-not $known) { return $false }
    $path = $uri.AbsolutePath.ToLowerInvariant()
    return ($path -like '*/singhramandeep101/pc-maintenance-kit/*' -or $path -like '*/singhramandeep101/pc-maintenance-kit')
}

function Test-ZipEntriesSafe {
    param([string]$ZipPath, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -EA SilentlyContinue
    $zip = $null
    try {
        $destRoot = [System.IO.Path]::GetFullPath($Destination)
        if (-not $destRoot.EndsWith('\')) { $destRoot = $destRoot + '\' }
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        foreach ($entry in $zip.Entries) {
            $name = ([string]$entry.FullName).Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($name.StartsWith('\') -or $name.StartsWith('..') -or $name.Contains('..\')) { return $false }
            $target = [System.IO.Path]::GetFullPath((Join-Path $Destination $name.TrimStart('\')))
            if (-not $target.StartsWith($destRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        return $true
    } catch {
        return $false
    } finally {
        if ($zip) { $zip.Dispose() }
    }
}

function Select-KitZip($Assets) {
    $zips = @($Assets | Where-Object { $_.name -match '\.zip$' -and $_.name -notmatch '\.sha256' -and $_.browser_download_url })
    $named = @($zips | Where-Object { $_.name -like 'PC-Maintenance-Kit-v*.zip' })
    if ($named.Count -gt 0) { return $named[0] }
    return ($zips | Select-Object -First 1)
}

function Get-ReleaseDownload {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $Headers
    $zip = Select-KitZip @($rel.assets)
    if (-not $zip) { return $null }

    $expected = $null
    $wantSum = [string]$zip.name + '.sha256'
    $sumAsset = @($rel.assets | Where-Object { $_.name -eq $wantSum -and $_.browser_download_url } | Select-Object -First 1)
    if (-not $sumAsset) {
        $sumAsset = @($rel.assets | Where-Object { $_.name -match '\.sha256$' -and $_.browser_download_url } | Select-Object -First 1)
    }
    if ($sumAsset -and -not (Test-TrustedKitDownloadUrl ([string]$sumAsset.browser_download_url))) {
        $sumAsset = $null
    }
    if ($sumAsset) {
        try {
            $sumPath = Join-Path $Work 'expected.sha256'
            Invoke-WebRequest -Uri $sumAsset.browser_download_url -OutFile $sumPath -UseBasicParsing -Headers @{ 'User-Agent' = 'PC-Maintenance-Kit' }
            $expected = Get-ExpectedSha256 (Get-Content -LiteralPath $sumPath -Raw -EA SilentlyContinue)
        } catch {
            # Keep going — GitHub asset digest may still provide the hash.
            $expected = $null
        }
    }
    if (-not $expected -and $zip.digest) {
        $expected = Get-ExpectedSha256 ([string]$zip.digest)
    }
    return [pscustomobject]@{
        Url      = [string]$zip.browser_download_url
        Name     = [string]$zip.name
        Expected = $expected
        Tag      = [string]$rel.tag_name
    }
}

function Unblock-Tree([string]$Path) {
    Get-ChildItem -LiteralPath $Path -Recurse -File -EA SilentlyContinue | ForEach-Object {
        try { Unblock-File -LiteralPath $_.FullName -EA SilentlyContinue } catch { }
    }
}

function Assert-ScriptsSafe([string]$Folder) {
    # Unsigned is allowed. A signature that exists must be Valid.
    Get-ChildItem -LiteralPath $Folder -Recurse -Filter *.ps1 -File -EA SilentlyContinue | ForEach-Object {
        $sig = Get-AuthenticodeSignature -FilePath $_.FullName
        $status = [string]$sig.Status
        if ($status -eq 'NotSigned') { return }
        if ($status -ne 'Valid') {
            throw ("Rejected {0}: Authenticode status is {1}" -f $_.Name, $status)
        }
    }
}

function Resolve-PayloadRoot([string]$Extract) {
    foreach ($cand in @(Get-ChildItem -LiteralPath $Extract -Recurse -Filter 'PC-Maintenance.ps1' -File -EA SilentlyContinue)) {
        $root = Split-Path -Parent $cand.FullName
        if (Test-Path -LiteralPath (Join-Path $root 'lib\Core.ps1')) { return $root }
    }
    return $null
}

function Test-PayloadHealthy([string]$Root) {
    $entry = Join-Path $Root 'PC-Maintenance.ps1'
    $core = Join-Path $Root 'lib\Core.ps1'
    if (-not (Test-Path -LiteralPath $entry)) { return $false }
    if (-not (Test-Path -LiteralPath $core)) { return $false }
    foreach ($f in @($entry, $core)) {
        $errs = $null
        $toks = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) { return $false }
    }
    return $true
}

Write-Host ""
Write-Host "  PC Maintenance Kit" -ForegroundColor Cyan
Write-Host "  Downloading from GitHub..." -ForegroundColor DarkGray

New-Item -ItemType Directory -Path $Work -Force | Out-Null
try {
    $zipPath = Join-Path $Work 'kit.zip'
    try {
        $info = Get-ReleaseDownload
    } catch {
        throw ("Could not fetch GitHub release info: {0}`nCheck your network connection and try again." -f $_.Exception.Message)
    }

    if (-not ($info -and $info.Url)) {
        throw "No GitHub release ZIP found. Publish a Release with PC-Maintenance-Kit-vX.Y.Z.zip (+ .sha256), or download manually."
    }

    Write-Host ("  Release {0}" -f $info.Tag) -ForegroundColor DarkGray
    if (-not (Test-TrustedKitDownloadUrl $info.Url)) {
        throw "Refusing to download from an unexpected address."
    }
    Invoke-WebRequest -Uri $info.Url -OutFile $zipPath -UseBasicParsing -Headers @{ 'User-Agent' = 'PC-Maintenance-Kit' }

    if (-not (Test-Path -LiteralPath $zipPath) -or ((Get-Item -LiteralPath $zipPath).Length -lt 1000)) {
        throw "Download failed or file was empty."
    }
    try { Unblock-File -LiteralPath $zipPath -EA SilentlyContinue } catch { }

    if (-not $info.Expected) {
        throw "Release has no SHA256 checksum attached. Refusing to install without integrity verification."
    }
    $got = Test-Sha256File -Path $zipPath -Expected $info.Expected
    Write-Host ("  SHA256 OK  {0}" -f $got) -ForegroundColor Green

    $extract = Join-Path $Work 'extract'
    if (-not (Test-ZipEntriesSafe -ZipPath $zipPath -Destination $extract)) {
        throw "Refusing to extract this ZIP because an entry escapes the folder."
    }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force
    Unblock-Tree $extract
    $source = Resolve-PayloadRoot $extract
    if (-not $source) { throw "Download did not contain PC-Maintenance.ps1 next to lib\Core.ps1." }
    Assert-ScriptsSafe $source
    if (-not (Test-PayloadHealthy $source)) { throw "Download failed its health check." }

    if (-not (Test-Path -LiteralPath $Dest)) {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }

    $rc = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    $backup = Join-Path $env:LOCALAPPDATA 'PC-Maintenance-Kit-backup'
    $hadInstall = Test-Path -LiteralPath (Join-Path $Dest 'PC-Maintenance.ps1')
    if ($hadInstall) {
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force -EA SilentlyContinue }
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        & $rc $Dest $backup /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Could not back up the current install (robocopy $LASTEXITCODE)." }
    }
    try {
        & $rc $source $Dest /E /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP /XD .git tests dist .github | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Could not copy files (robocopy $LASTEXITCODE)." }

        # Drop scripts removed from newer releases (robocopy /E does not delete extras)
        foreach ($rel in @('', 'lib')) {
            $srcDir = if ($rel) { Join-Path $source $rel } else { $source }
            $dstDir = if ($rel) { Join-Path $Dest $rel } else { $Dest }
            if (-not (Test-Path -LiteralPath $srcDir)) { continue }
            if (-not (Test-Path -LiteralPath $dstDir)) { continue }
            Get-ChildItem -LiteralPath $dstDir -File -Filter '*.ps1' -EA SilentlyContinue | ForEach-Object {
                $peer = Join-Path $srcDir $_.Name
                if (-not (Test-Path -LiteralPath $peer)) {
                    Remove-Item -LiteralPath $_.FullName -Force -EA SilentlyContinue
                }
            }
        }

        Unblock-Tree $Dest
        if (-not (Test-PayloadHealthy $Dest)) { throw "Installed copy failed its health check." }
    } catch {
        if ($hadInstall -and (Test-Path -LiteralPath (Join-Path $backup 'PC-Maintenance.ps1'))) {
            Write-Host "  Install failed. Restoring the previous copy..." -ForegroundColor Yellow
            & $rc $backup $Dest /E /IS /IT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        }
        throw
    }

    $startBat = Join-Path $Dest 'Start.bat'
    $scriptPs1 = Join-Path $Dest 'PC-Maintenance.ps1'
    if (-not (Test-Path -LiteralPath $scriptPs1)) {
        throw "Install finished but PC-Maintenance.ps1 is missing."
    }

    try {
        $ws = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnk = $ws.CreateShortcut((Join-Path $desktop 'PC Maintenance Kit.lnk'))
        if (Test-Path -LiteralPath $startBat) {
            $lnk.TargetPath = $startBat
        } else {
            $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$scriptPs1`" -Mode Gui"
        }
        $lnk.WorkingDirectory = $Dest
        $lnk.Description = 'PC Maintenance Kit'
        $lnk.Save()
    } catch { }

    Write-Host "  Installed to $Dest" -ForegroundColor Green
    Write-Host "  Opening the app (Windows may ask for Administrator)..." -ForegroundColor DarkGray
    Write-Host ""

    if (Test-Path -LiteralPath $startBat) {
        Start-Process -FilePath $startBat -WorkingDirectory $Dest
    } else {
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $ps -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden',
            '-File', $scriptPs1, '-Mode', 'Gui'
        ) -WorkingDirectory $Dest
    }
} finally {
    Start-Sleep -Milliseconds 400
    try { Remove-Item -LiteralPath $Work -Recurse -Force -EA SilentlyContinue } catch { }
}
