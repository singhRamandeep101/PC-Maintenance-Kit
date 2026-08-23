#Requires -Version 5.1
param(
    [string]$Version = "5.1.4"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dist = Join-Path $Root "dist"
$Stage = Join-Path $Dist ("PC-Maintenance-Kit-v" + $Version)
$Zip = Join-Path $Dist ("PC-Maintenance-Kit-v" + $Version + ".zip")

if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
if (Test-Path $Zip) { Remove-Item $Zip -Force }
New-Item -ItemType Directory -Path (Join-Path $Stage "lib") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Stage "docs") -Force | Out-Null

Copy-Item (Join-Path $Root "Start.bat") $Stage
Copy-Item (Join-Path $Root "PC-Maintenance.ps1") $Stage
Copy-Item (Join-Path $Root "Get.ps1") $Stage -EA SilentlyContinue
Copy-Item (Join-Path $Root "README.md") $Stage
Copy-Item (Join-Path $Root "LICENSE") $Stage
Copy-Item (Join-Path $Root "lib\*.ps1") (Join-Path $Stage "lib")
if (Test-Path (Join-Path $Root "docs\screenshots")) {
    Copy-Item (Join-Path $Root "docs\screenshots\*") (Join-Path $Stage "docs") -Force -EA SilentlyContinue
}
if (Test-Path (Join-Path $Root "tests")) {
    New-Item -ItemType Directory -Path (Join-Path $Stage "tests") -Force | Out-Null
    Copy-Item (Join-Path $Root "tests\*.ps1") (Join-Path $Stage "tests") -Force -EA SilentlyContinue
}

Compress-Archive -Path $Stage -DestinationPath $Zip -Force
Write-Host "Created: $Zip"
Write-Host "Extract and double-click Start.bat"
