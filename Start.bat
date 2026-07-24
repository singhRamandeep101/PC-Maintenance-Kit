@echo off
title PC Maintenance v4
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PC-Maintenance.ps1" -Mode Gui
