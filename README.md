# PC Maintenance Kit v5

Gamer-focused Windows maintenance toolkit with a tabbed dark GUI (WMT-inspired, not a full sysadmin suite).

Built for weekly cleanup, gaming optimizations, controlled updates, and optional repair on Windows 10/11 gaming PCs.

## Quick start

1. Download or clone this repo  
2. Double-click **Start.bat**  
3. Allow the UAC prompt  
4. Use the tabs — start with **Home → Run Weekly Full**

## Tabs

| Tab | What it does |
|-----|----------------|
| **Home** | Device snapshot + Weekly Full (cleanup + gaming opts; WU/winget off by default) |
| **Cleanup** | Temp, browsers, Recycle Bin, GPU shader caches; optional Steam/Epic/Riot caches (confirm) |
| **Updates** | Windows Update and/or winget; open AMD Adrenalin / NVIDIA App |
| **Gaming** | Game Mode on, Game DVR/ReLive off, Ultimate Performance, Discord HW accel off |
| **Repair** | Restore point + DISM/SFC (slow; confirm required) |
| **Device** | CPU/GPU/RAM channels, SSD health, free space, reboot pending |

## Safety

- Weekly Full does **not** run Windows Update / winget unless you check those boxes  
- Launcher cache cleanup asks for confirmation  
- Repair asks for confirmation  
- Pending restart is detected and shown after runs  
- Windows Update download-cache wipe is skipped when updates run in the same session  

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

**Full** mode = weekly gamer defaults (cleanup + shaders + gaming optimize; updates off).  
**FullRepair** = everything including updates + DISM/SFC.

## Requirements

- Windows 10/11  
- PowerShell 5.1+  
- Administrator  

## Not included (on purpose)

Firewall editor, hosts adblock, mass debloat, registry cleaners, 100+ privacy toggles, full package-manager zoo. Keep the tool trustworthy for gamers.

## License

MIT
