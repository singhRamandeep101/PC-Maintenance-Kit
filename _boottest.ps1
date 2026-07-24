param([string]$Mode = "Gui")
$log = Join-Path $env:TEMP "pcmaint-boot.log"
try {
  "BOOT $(Get-Date) Mode=$Mode PID=$PID" | Out-File $log
  "PSCommandPath=$PSCommandPath" | Out-File $log -Append
  "Args=$($args -join '|')" | Out-File $log -Append
  $Script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  "AppRoot=$Script:AppRoot" | Out-File $log -Append
  . (Join-Path $Script:AppRoot "lib\Core.ps1")
  "Core loaded" | Out-File $log -Append
  . (Join-Path $Script:AppRoot "lib\Gui.ps1")
  "Gui loaded" | Out-File $log -Append
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = [Security.Principal.WindowsPrincipal]::new($id)
  $admin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  "IsAdmin=$admin" | Out-File $log -Append
  if (-not $admin) {
    "Not admin - would elevate" | Out-File $log -Append
    exit 2
  }
  "Calling Show-MaintenanceGui" | Out-File $log -Append
  Show-MaintenanceGui
  "Gui closed normally" | Out-File $log -Append
} catch {
  "ERROR: $($_.Exception.Message)" | Out-File $log -Append
  $_ | Out-String | Out-File $log -Append
  exit 1
}
