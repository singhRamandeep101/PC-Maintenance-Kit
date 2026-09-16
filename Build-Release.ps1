#Requires -Version 5.1
param(
    [string]$Version = "",
    [string]$CertThumbprint = $env:PCMK_SIGN_THUMBPRINT,
    [string]$PfxPath = "",
    [string]$PfxPassword = $env:PCMK_SIGN_PFX_PASSWORD
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# VERSION is the only source of truth. An explicit -Version must agree with it,
# otherwise the ZIP name and the VERSION inside it silently disagree.
$versionFile = Join-Path $Root "VERSION"
if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "VERSION file not found at $versionFile"
}
$fileVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
if (-not $fileVersion) { throw "VERSION file is empty" }
if (-not $Version) {
    $Version = $fileVersion
} elseif ($Version -ne $fileVersion) {
    throw "-Version '$Version' does not match VERSION file '$fileVersion'. Bump VERSION first."
}

$Dist = Join-Path $Root "dist"
$Stage = Join-Path $Dist ("PC-Maintenance-Kit-v" + $Version)
$Zip = Join-Path $Dist ("PC-Maintenance-Kit-v" + $Version + ".zip")
$ShaFile = $Zip + ".sha256"

function Get-SigningCertificate {
    if ($env:PCMK_SIGN_PFX_BASE64) {
        $bytes = [Convert]::FromBase64String($env:PCMK_SIGN_PFX_BASE64)
        $tempPfx = Join-Path $env:TEMP ("pcmk-sign-" + [guid]::NewGuid().ToString("N") + ".pfx")
        [System.IO.File]::WriteAllBytes($tempPfx, $bytes)
        $script:CleanupPfx = $tempPfx
        $pwdText = $PfxPassword
        if (-not $pwdText) { $pwdText = $env:PCMK_SIGN_PFX_PASSWORD }
        if (-not $pwdText) { throw "PCMK_SIGN_PFX_BASE64 is set but no PFX password was provided." }
        $securePwd = ConvertTo-SecureString $pwdText -AsPlainText -Force
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $tempPfx,
            $securePwd,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        )
    }
    if ($PfxPath -and (Test-Path -LiteralPath $PfxPath)) {
        if (-not $PfxPassword) { throw "PfxPath requires -PfxPassword or PCMK_SIGN_PFX_PASSWORD." }
        $securePwd = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $PfxPath,
            $securePwd,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        )
    }
    if ($CertThumbprint) {
        $thumb = ($CertThumbprint -replace '\s', '').ToUpperInvariant()
        $found = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -EA SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $thumb } |
            Select-Object -First 1
        if (-not $found) { throw "No certificate found with thumbprint $thumb." }
        return $found
    }
    return $null
}

function Invoke-AuthenticodeSign {
    param([string]$Folder, $Certificate)
    $files = @(Get-ChildItem -LiteralPath $Folder -Recurse -Filter *.ps1 -File)
    if ($files.Count -eq 0) { throw "No PowerShell files to sign in $Folder" }
    $stamp = "http://timestamp.digicert.com"
    foreach ($f in $files) {
        $sig = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $Certificate -HashAlgorithm SHA256 -TimestampServer $stamp
        if ($sig.Status -ne 'Valid') {
            throw ("Authenticode failed for {0}: {1} ({2})" -f $f.Name, $sig.Status, $sig.StatusMessage)
        }
    }
    Write-Host ("Signed {0} script(s) with {1}" -f $files.Count, $Certificate.Subject)
}

try {
    if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
    if (Test-Path $Zip) { Remove-Item $Zip -Force }
    if (Test-Path $ShaFile) { Remove-Item $ShaFile -Force }
    New-Item -ItemType Directory -Path (Join-Path $Stage "lib") -Force | Out-Null

    # Required payload - a missing file here must fail the build, not ship silently
    foreach ($name in @("Start.bat", "PC-Maintenance.ps1", "Get.ps1", "README.md", "LICENSE", "VERSION")) {
        $src = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $src)) { throw "Release payload missing: $name" }
        Copy-Item $src $Stage
    }
    if (Test-Path -LiteralPath (Join-Path $Root "CHANGELOG.md")) {
        Copy-Item (Join-Path $Root "CHANGELOG.md") $Stage
    }
    Copy-Item (Join-Path $Root "lib\*.ps1") (Join-Path $Stage "lib")

    # README links docs/screenshots/*.png - ship them or every release has broken images
    $docsSrc = Join-Path $Root "docs"
    if (Test-Path -LiteralPath $docsSrc) {
        Copy-Item $docsSrc $Stage -Recurse -Force
    }

    $stagedLibs = @(Get-ChildItem -LiteralPath (Join-Path $Stage "lib") -Filter *.ps1 -File)
    if ($stagedLibs.Count -lt 1) { throw "No lib scripts were staged" }

    $cert = Get-SigningCertificate
    if ($cert) {
        Invoke-AuthenticodeSign -Folder $Stage -Certificate $cert
    } else {
        Write-Host "Authenticode skipped (no certificate). Set PCMK_SIGN_PFX_BASE64 or -CertThumbprint to sign."
    }

    Compress-Archive -Path $Stage -DestinationPath $Zip -Force
    $hash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLowerInvariant()
    $zipName = Split-Path $Zip -Leaf
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ShaFile, ("{0}  {1}`n" -f $hash, $zipName), $utf8)

    Write-Host "Created: $Zip"
    Write-Host "SHA256:  $hash"
    Write-Host "Checksum file: $ShaFile"
    Write-Host "Extract and double-click Start.bat"
} finally {
    if ($script:CleanupPfx -and (Test-Path -LiteralPath $script:CleanupPfx)) {
        Remove-Item -LiteralPath $script:CleanupPfx -Force -EA SilentlyContinue
    }
}
