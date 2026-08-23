#Requires -Version 5.1
<#
.SYNOPSIS
    Download and launch PC Maintenance Kit.

.DESCRIPTION
    Installs the latest GitHub code to %LOCALAPPDATA%\PC-Maintenance-Kit
    and opens the app. Administrator permission is requested on launch.

.EXAMPLE
    irm https://raw.githubusercontent.com/singhRamandeep101/PC-Maintenance-Kit/main/Get.ps1 | iex
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'singhRamandeep101/PC-Maintenance-Kit'
$Dest = Join-Path $env:LOCALAPPDATA 'PC-Maintenance-Kit'
$Work = Join-Path $env:TEMP ('PCMK-get-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$Headers = @{ 'User-Agent' = 'PC-Maintenance-Kit' }
$ZipUrl = "https://github.com/$Repo/archive/refs/heads/main.zip"

Write-Host ""
Write-Host "  PC Maintenance Kit" -ForegroundColor Cyan
Write-Host "  Downloading from GitHub..." -ForegroundColor DarkGray

New-Item -ItemType Directory -Path $Work -Force | Out-Null
try {
    $url = $ZipUrl
    $zipPath = Join-Path $Work 'kit.zip'
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -Headers $Headers
    if (-not (Test-Path -LiteralPath $zipPath) -or ((Get-Item -LiteralPath $zipPath).Length -lt 1000)) {
        throw "Download failed or file was empty."
    }

    $extract = Join-Path $Work 'extract'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force
    $payload = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'PC-Maintenance.ps1' -File -EA SilentlyContinue |
        Select-Object -First 1
    if (-not $payload) { throw "Download did not contain PC-Maintenance.ps1." }
    $source = Split-Path -Parent $payload.FullName

    if (-not (Test-Path -LiteralPath $Dest)) {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }

    $rc = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    & $rc $source $Dest /E /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP /XD .git | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Could not copy files (robocopy $LASTEXITCODE)." }

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
