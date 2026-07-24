@echo off
title PC Maintenance Kit v5
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0PC-Maintenance.ps1" -Mode Gui
if errorlevel 1 (
  echo.
  echo Something went wrong. Check Desktop\PC-Maintenance-Logs for boot-error logs.
  pause
)
