# PC Maintenance Kit v5.1

Gamer-focused Windows maintenance toolkit with a tabbed dark GUI.

Built for weekly cleanup, gaming optimizations, controlled updates, and optional repair on Windows 10/11 gaming PCs.

## Screenshots

![Home tab](docs/screenshots/home-tab.png)

![Gaming tab](docs/screenshots/gaming-tab.png)

## Quick start

### Easiest (friends)
1. Grab the release ZIP from `dist\PC-Maintenance-Kit-v5.1.0.zip` (or GitHub Releases when published)
2. Extract anywhere
3. Double-click **Start.bat**
4. Allow UAC — the console stays hidden; only the app window opens

### From source
1. Clone this repo  
2. Double-click **Start.bat**

## Tabs

| Tab | What it does |
|-----|----------------|
| **Home** | Device snapshot + Weekly Full (cleanup + gaming opts; WU/winget off by default) |
| **Cleanup** | Temp, browsers, Recycle Bin, GPU shader caches; optional Steam/Epic/Riot caches (confirm) |
| **Updates** | Windows Update and/or winget; open AMD Adrenalin / NVIDIA App |
| **Gaming** | Status + apply optimize, fix power plan, Discord HW accel off |
| **Repair** | Restore point + DISM/SFC (slow; confirm required) |
| **Device** | Specs + actions: copy RAM tip, storage settings, restart |

## Safety

- Weekly Full does **not** run Windows Update / winget unless you check those boxes  
- Launcher cache cleanup asks for confirmation  
- Repair asks for confirmation  
- Pending restart is detected and shown after runs  
- Live status bar shows Ready/Busy, Admin, free space, and current job  

## Build a local ZIP

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1 -Version 5.1.0
```

Output: `dist\PC-Maintenance-Kit-v5.1.0.zip`

## Logs

`Desktop\PC-Maintenance-Logs\`

## CLI

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode Gui
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode Cli
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode Full
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode CleanupOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode UpdatesOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode Repair
powershell -NoProfile -ExecutionPolicy Bypass -File .\PC-Maintenance.ps1 -Mode FullRepair
```

**Full** = weekly gamer defaults (cleanup + shaders + gaming optimize; updates off).  
**FullRepair** = everything including updates + DISM/SFC.

## Requirements

- Windows 10/11  
- PowerShell 5.1+  
- Administrator  

## Not included (on purpose)

Firewall editor, hosts adblock, mass debloat, registry cleaners, 100+ privacy tweaks.

## License

MIT
