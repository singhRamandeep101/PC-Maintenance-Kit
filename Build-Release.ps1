#Requires -Version 5.1
param(
    [string]$Version = "5.1.6",
    [string]$CertThumbprint = $env:PCMK_SIGN_THUMBPRINT,
    [string]$PfxPath = "",
    [string]$PfxPassword = $env:PCMK_SIGN_PFX_PASSWORD
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
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
        $pwd = ConvertTo-SecureString $pwdText -AsPlainText -Force
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $tempPfx,
            $pwd,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        )
    }
    if ($PfxPath -and (Test-Path -LiteralPath $PfxPath)) {
        if (-not $PfxPassword) { throw "PfxPath requires -PfxPassword or PCMK_SIGN_PFX_PASSWORD." }
        $pwd = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $PfxPath,
            $pwd,
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

    Copy-Item (Join-Path $Root "Start.bat") $Stage
    Copy-Item (Join-Path $Root "PC-Maintenance.ps1") $Stage
    Copy-Item (Join-Path $Root "README.md") $Stage
    Copy-Item (Join-Path $Root "LICENSE") $Stage
    Copy-Item (Join-Path $Root "lib\*.ps1") (Join-Path $Stage "lib")

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
