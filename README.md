# PC Maintenance Kit

Windows maintenance tool with a simple GUI. Cleans temp/browser caches, runs updates, checks gaming-related settings, and can repair Windows with DISM/SFC.

Requires Windows 10/11 and Administrator permission.

## Quick start

1. Download or clone this repo
2. Double-click **Start.bat**
3. Allow the UAC prompt
4. Pick a mode and click **Run**

## Modes

| Mode | What it does |
|------|----------------|
| **Full run** | Restore point, cleanup, Windows Update, winget, AMD Adrenalin, health checks |
| **Cleanup only** | Temp files, browser caches, Recycle Bin |
| **Updates only** | Restore point, Windows Update, winget, AMD |
| **Repair** | DISM + SFC (slow; use when Windows feels broken) |
| **Full + Repair** | Everything including DISM/SFC |

## Options

- **Create restore point** — recommended before updates/repair
- **Open AMD Adrenalin** — opens the app so you can check GPU drivers (skipped if not installed)
- **Temp age (days)** — only delete temp files older than this (default 2)

## Logs

Every run writes a log to:

`Desktop\PC-Maintenance-Logs\`

Use **Open logs** in the GUI to jump there.

## CLI

```bat
Start.bat
```

Or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode Gui
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode Cli
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode Full
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode CleanupOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode UpdatesOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode Repair
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode FullRepair
```

## Notes

- Close browsers before cleanup for best results
- Repair can take 10–30+ minutes
- Xbox Game DVR / AMD ReLive are turned off during health checks if found enabled
- No third-party “optimizer” junk — only built-in Windows tools + winget

## License

MIT
