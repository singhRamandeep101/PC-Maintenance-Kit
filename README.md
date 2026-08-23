# PC Maintenance Kit

Gamer-focused Windows maintenance toolkit with a tabbed dark GUI.

Built for weekly cleanup, gaming optimizations, controlled updates, and optional repair on Windows 10/11 gaming PCs.

## Run it

Copy this into **PowerShell** (Windows 10/11) and press Enter:

```powershell
irm https://raw.githubusercontent.com/singhRamandeep101/PC-Maintenance-Kit/main/Get.ps1 | iex
```

That downloads the latest code from GitHub, installs it to `%LOCALAPPDATA%\PC-Maintenance-Kit`, puts a shortcut on the Desktop, and opens the app. Windows will ask for Administrator permission.

You can read [Get.ps1](Get.ps1) first — it is short and does not hide anything.

### Already cloned this repo?

Double-click **Start.bat**. The console stays hidden; only the app window opens.

## Screenshots

![Home tab](docs/screenshots/home-tab.png)

![Gaming tab](docs/screenshots/gaming-tab.png)

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

- Requires **Administrator** — it cleans system temp, can install updates, and can run DISM/SFC
- Weekly Full does **not** run Windows Update / winget unless you check those boxes
- Launcher cache cleanup asks for confirmation
- Repair asks for confirmation
- Pending restart is detected and shown after runs
- Live status bar shows Ready/Busy, Admin, free space, and current job
- Older versions wrote files to `Desktop\PC-Maintenance-Logs` — you can delete that folder if it is still there

## CLI

From the repo folder:

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

## Build a local ZIP

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1 -Version 5.1.4
```

Output: `dist\PC-Maintenance-Kit-v5.1.4.zip`

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Administrator

## Not included (on purpose)

Firewall editor, hosts adblock, mass debloat, registry cleaners, 100+ privacy tweaks.

## License

MIT
