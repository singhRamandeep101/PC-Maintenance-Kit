@echo off
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0PC-Maintenance.ps1" -Mode Gui
if errorlevel 1 (
  echo.
  echo Something went wrong. A details window should have appeared.
  pause
)
