#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Gui','Cli','Full','CleanupOnly','UpdatesOnly','Repair','FullRepair')]
    [string]$Mode = 'Gui',
    [int]$TempOlderThanDays = 2
)

$ErrorActionPreference = 'Continue'
$Script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Script:AppRoot "lib\Core.ps1")
. (Join-Path $Script:AppRoot "lib\Gui.ps1")

$relaunch = ""
if ($Mode -ne 'Gui') { $relaunch = "-Mode $Mode" }
if ($TempOlderThanDays -ne 2) { $relaunch += " -TempOlderThanDays $TempOlderThanDays" }
Ensure-Admin -RelaunchArgs $relaunch.Trim()

$host.UI.RawUI.WindowTitle = "PC Maintenance v4"
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
