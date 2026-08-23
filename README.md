# PC Maintenance Kit

Gamer-focused Windows 10/11 maintenance toolkit. Cleanup, gaming tweaks, controlled updates, and optional DISM/SFC repair — in a dark tabbed GUI.

## Run it

Copy this into **PowerShell** and press Enter:

```powershell
irm https://raw.githubusercontent.com/singhRamandeep101/PC-Maintenance-Kit/main/Get.ps1 | iex
```

That downloads the latest code from GitHub, installs it to `%LOCALAPPDATA%\PC-Maintenance-Kit`, adds a Desktop shortcut, and opens the app. Windows will ask for Administrator permission.

You can read [Get.ps1](Get.ps1) first — it is short and does not hide anything. The installer checks the release ZIP SHA256 before extracting.

Already have the repo? Double-click **Start.bat**.

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

## Verify a download

Every GitHub Release includes `PC-Maintenance-Kit-vX.Y.Z.zip` and `PC-Maintenance-Kit-vX.Y.Z.zip.sha256`.

```powershell
$zip = "$env:USERPROFILE\Downloads\PC-Maintenance-Kit-v5.1.6.zip"
$want = (Get-Content "$zip.sha256" -Raw)
if ($want -notmatch '([A-Fa-f0-9]{64})') { throw 'Checksum file is missing a hash.' }
$got = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($got -ne $Matches[1]) { throw "SHA256 mismatch. expected=$($Matches[1]) actual=$got" }
Unblock-File $zip
Write-Host "Checksum OK"
```

The one-line installer does this check for you.

## Windows SmartScreen

Downloaded files can show a SmartScreen / "unknown publisher" prompt because this project is not yet signed with a paid code-signing certificate. That is expected.

What this repo already does:

- Release ZIPs ship with a SHA256 file so you can confirm the bits were not altered
- `Get.ps1` verifies that hash, then runs `Unblock-File` (clears Mark of the Web on the install folder)
- `Build-Release.ps1` will Authenticode-sign every `.ps1` if you provide a certificate

To sign a build you already have:

```powershell
# Certificate in your Windows cert store
.\Build-Release.ps1 -Version 5.1.6 -CertThumbprint 'THUMBPRINT'

# Or a PFX file
.\Build-Release.ps1 -Version 5.1.6 -PfxPath 'C:\certs\pcmk.pfx' -PfxPassword 'your-password'
```

For GitHub Actions, add repository secrets `PCMK_SIGN_PFX_BASE64` (base64 of the .pfx) and `PCMK_SIGN_PFX_PASSWORD`. `Build-Release.ps1` picks those up automatically. SmartScreen reputation still takes time after you start signing; an EV code-signing cert from a public CA is what Microsoft uses for immediate reputation.

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
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-Release.ps1 -Version 5.1.6
```

Output: `dist\PC-Maintenance-Kit-v5.1.6.zip` and `dist\PC-Maintenance-Kit-v5.1.6.zip.sha256`

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Administrator

## Not included (on purpose)

Firewall editor, hosts adblock, mass debloat, registry cleaners, 100+ privacy tweaks.

## License

MIT
