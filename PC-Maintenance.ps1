#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Gui','Cli','Full','CleanupOnly','UpdatesOnly','Repair','FullRepair')]
    [string]$Mode = 'Gui',
    [int]$TempOlderThanDays = 2
)

$ErrorActionPreference = 'Stop'
if ($PSScriptRoot) {
    $Script:AppRoot = $PSScriptRoot
} elseif ($PSCommandPath) {
    $Script:AppRoot = Split-Path -Parent $PSCommandPath
} else {
    $Script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $Script:AppRoot -or -not (Test-Path -LiteralPath (Join-Path $Script:AppRoot "lib\Core.ps1"))) {
    throw "Cannot locate lib\Core.ps1. AppRoot='$Script:AppRoot'"
}

try {
    . (Join-Path $Script:AppRoot "lib\Core.ps1")
    . (Join-Path $Script:AppRoot "lib\Gaming.ps1")
    . (Join-Path $Script:AppRoot "lib\Device.ps1")
    . (Join-Path $Script:AppRoot "lib\Gui.ps1")

    $relaunch = "-Mode $Mode"
    if ($TempOlderThanDays -ne 2) { $relaunch += " -TempOlderThanDays $TempOlderThanDays" }
    Ensure-Admin -ScriptPath $PSCommandPath -RelaunchArgs $relaunch

    $ErrorActionPreference = 'Continue'
    try { $host.UI.RawUI.WindowTitle = "PC Maintenance Kit v5.1" } catch { }
    $Script:TempOlderThanDays = $TempOlderThanDays

    switch ($Mode) {
        'Gui' {
            Show-MaintenanceGui
        }
        'Cli' {
            Show-CliMenu
        }
        default {
            Apply-ModeFlags -ModeName $Mode
            [void](Invoke-MaintenanceRun)
            Write-Host ""
            Write-Host "  Press Enter to close..."
            [void][System.Console]::ReadLine()
        }
    }
}
catch {
    $msg = $_.Exception.Message
    $detail = $_ | Out-String
    try {
        $bootLog = Join-Path $env:USERPROFILE "Desktop\PC-Maintenance-Logs"
        if (-not (Test-Path $bootLog)) { New-Item -ItemType Directory -Path $bootLog -Force | Out-Null }
        $bootFile = Join-Path $bootLog "boot-error_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
        $detail | Out-File $bootFile -Encoding UTF8
    } catch { }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            "PC Maintenance failed to start:`n`n$msg",
            "PC Maintenance",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {
        Write-Host "PC Maintenance failed to start:" -ForegroundColor Red
        Write-Host $detail -ForegroundColor Red
        Write-Host "Press Enter to close..."
        [void][System.Console]::ReadLine()
    }
    exit 1
}
