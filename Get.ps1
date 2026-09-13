#Requires -Version 5.1
<#
.SYNOPSIS
    Download, verify, and launch PC Maintenance Kit.

.DESCRIPTION
    Installs the latest GitHub *release* ZIP to %LOCALAPPDATA%\PC-Maintenance-Kit
    after checking its SHA256 checksum. Refuses to install without a verified hash.
    Administrator permission is requested on launch.

.EXAMPLE
    irm https://raw.githubusercontent.com/singhRamandeep101/PC-Maintenance-Kit/main/Get.ps1 | iex
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

function Get-ReleaseDownload {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $Headers
    $zip = @($rel.assets) |
        Where-Object { $_.name -match '\.zip$' -and $_.name -notmatch '\.sha256' -and $_.browser_download_url } |
        Select-Object -First 1
    if (-not $zip) { return $null }

    $expected = $null
    $sumAsset = @($rel.assets) |
        Where-Object { $_.name -match '\.sha256$' -and $_.browser_download_url } |
        Select-Object -First 1
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
    Get-ChildItem -LiteralPath $Folder -Recurse -Filter *.ps1 -File -EA SilentlyContinue | ForEach-Object {
        $sig = Get-AuthenticodeSignature -FilePath $_.FullName
        if ($sig.Status -eq 'HashMismatch') {
            throw ("Rejected {0}: file was signed but has been modified" -f $_.Name)
        }
    }
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
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force
    Unblock-Tree $extract
    $payload = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'PC-Maintenance.ps1' -File -EA SilentlyContinue |
        Select-Object -First 1
    if (-not $payload) { throw "Download did not contain PC-Maintenance.ps1." }
    $source = Split-Path -Parent $payload.FullName
    Assert-ScriptsSafe $source

    if (-not (Test-Path -LiteralPath $Dest)) {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }

    $rc = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    & $rc $source $Dest /E /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP /XD .git tests dist docs .github | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Could not copy files (robocopy $LASTEXITCODE)." }
    Unblock-Tree $Dest

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
