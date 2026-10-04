# Changelog

## 5.6.0

winget asks which apps to update before it installs anything.

- A checklist opens with every available upgrade already checked. Uncheck the ones to leave alone
- Leave every app checked and they still install in one silent pass. Uncheck any, and only the checked apps are installed
- A scheduled run still updates every listed app and does not wait on the checklist
- If the window cannot open, the same choice is a numbered list: a number toggles a row, U updates, Q cancels

## 5.5.0

Security health is a status page. It reads Windows Defender, the firewall, and whether Malwarebytes is installed, then opens those apps. It does not scan or change protection settings.

- Security tab shows real-time protection, signature age, last scans, active threats, firewall profiles, and Malwarebytes
- Open Malwarebytes and Open Windows Security launch the apps. A missing Malwarebytes install does not mark the PC unprotected
- Home shows one Security line. A Defender scan older than 20 days holds the setup score at Needs work and shows the weighted total beside it. The biggest limiter is the category that costs the most points. A repeat read within 10 seconds reuses the last result. The window updates when you refresh or run an action
- Temp cleanup no longer touches Windows Internet cache or the WebCache database
- Gaming lists the apps actually set to start with Windows, including Store apps, and ignores ones you already turned off. If that app's service is still set to start, the list says so. A sign-in task is listed only when its name reads like an app name
- The installer and self-update start a download only from this repository on github.com, and they refuse a ZIP entry that escapes the install folder. The checksum is still the one published with that release
- Opening Home, Gaming, or Security reads security and the score again once the last result is older than 10 seconds. The window does not poll in the background
- Open Startup apps opens the Startup apps page. Recommendations name real apps, and internal sign-in task ids are left out
- A service match uses the service file path, including the DLL behind svchost. A short name no longer matches a longer folder name. Extra sign-in tasks with a readable name lower the startup check to a warning and open Startup apps
- CLI option 7 prints the same report and does not launch anything

## 5.4.2

Home, Cleanup, and Updates use the same cards as the rest of the window. The setup score weighs settings you can change more than the hardware you already own. Stop no longer kills DISM or SFC. The weekly task does not install updates unless you opt in, and Home shows what the last run did.

- Setup score weights: power, game features, startup, and reboot outweigh disk type and RAM
- Stop leaves a DISM or SFC process running until Windows finishes it, then skips the steps that have not started
- The Sunday task installs Windows Update or winget only when "Weekly task may install updates" is on
- Home shows the last scheduled run, including which flags it used
- The one-line installer example points at the `v5.4.2` tag, which does not move after release
- Window resize and score text no longer throw "Update-StackLayout is not recognized"
- Stop leaves a winget upgrade or Windows Update install running until it finishes
- The Sunday task does not clear shader caches or change gaming settings unless that box is on, and it starts with RemoteSigned after the download mark is cleared
- Cleanup, disk probes, and saved settings report a failure instead of continuing with no message

## 5.4.1

Gaming, Repair, and Device use the same slate cards as the rest of the window: a score hero, live status, and the actions that were already on those tabs.

- Gaming shows the score, letter grade, live Game Mode / DVR / power / Discord rows, and the top fixes
- Repair shows what DISM + SFC will do before the confirm, and keeps the restore-point checkbox
- Device lists the live hardware rows, the RAM tip, and the same storage, refresh, update, and restart actions

## 5.4.0

Cleanup stays inside the folder it was given, scheduled runs no longer hang on dialogs, and the score stops awarding points for probes that failed.

**Safety**

- Recursive deletes walk the tree themselves and skip junctions and symlinks, so a link inside Temp or a cache folder cannot pull the delete outside that folder
- The Windows Update download-cache wipe uses that same walk instead of `Remove-Item -Recurse`
- `Test-SafeCleanupPath` now refuses children of Documents, Desktop, other user profiles, and everything under Windows except `Temp` and `SoftwareDistribution\Download`
- Epic cleanup no longer wipes `Saved\Data` (launcher state, not a cache)
- Installer and self-update prefer the `PC-Maintenance-Kit-v*.zip` asset, require `PC-Maintenance.ps1` beside `lib\Core.ps1`, and reject a script whose Authenticode signature is present but not `Valid`
- `Get.ps1` backs up the current install and restores it if the copy or health check fails
- A scheduled run writes `scheduled-last-run.log` and does not show message boxes. winget still runs only when that checkbox was saved on
- Cleanup-only runs no longer start Windows Update or BITS if you stopped them
- DISM and SFC count as success only when the exit code is 0
- An unrecognized CLI menu choice does nothing

**Fixes**

- Ultimate Performance is created once. The plan you left is saved, and Gaming has **Restore previous power plan**
- Optimization score gives storage, memory, power, and display zero points when those probes fail. `Unspecified` disk media is no longer scored as an SSD
- winget bulk upgrades report install failures instead of a clean success
- winget no longer falls back to upgrading one app at a time. One silent `upgrade --all` covers the normal list, so installer windows are not opened in a queue
- Packages winget marks as needing explicit targeting (Unity editors and the same class of app) are upgraded silently one id at a time and each result is written to the log. If an installer has no silent mode, the kit says so and does not open a window
- Apps whose installed version winget cannot determine are named and left alone
- Panel refresh after cleanup or updates no longer reloads CPU, GPU, and disk. Those probes stay cached, and disk info is read without importing the Storage module
- The window uses one slate palette with light body text, so labels, checkboxes, the log, and disabled buttons stay readable
- Resizing no longer clips text or stacks controls. Cards are not cut to a rounded region, and the minimum size grows with display scaling
- The window is a left-hand nav and scrolling pages. Labels wrap inside the column, buttons wrap onto the next line, and the activity log can be hidden so it does not cover the page
- Page text is stacked from each label's real height, so wrapped lines no longer paint over the next row. Icon glyphs sit in circles instead of sharp squares
- Pages keep the title at the top. The activity-log links sit to the right of the title, and long gaming status values stay on their own side of the row
- Startup reads C: and the GPU list once and reuses them for free space, drive size, and the score. Cleanup preview no longer measures the same temp folder twice
- Home shows Fix my PC, the options, and the presets before the hardware cards. Cleanup preview counts sizes without a script call per file and updates the status while a folder is still being measured
- Stop during a cleanup preview now ends the size walk, including the rest of the current folder. Startup and Refresh lock the window while they read hardware, so another action cannot start in the middle of that scan
- Update check treats an unparseable remote version as unavailable, not "up to date"
- Windows temp and the update download cache use `%SystemRoot%` instead of a hardcoded `C:\Windows`

## 5.3.0

Gaming Optimization Score, plus a safety and release-engineering pass.

**New**

- Gaming Optimization Score: 0–100 config/setup score with category breakdown and top fixes
- Home tab: score hero + **Fix my PC for gaming** CTA with before/after score
- Home presets: **Gamer** / **Quiet** / **Full** fill Weekly checkboxes in one click
- Optional **Schedule Weekly Full** (Task Scheduler, Sundays 6 PM, `-Mode Scheduled`)
- Gaming tab: score header, scan + apply recommended fixes; Device summary shows score line
- CLI option `[6]` prints the optimization score report
- GUI page builders split into `lib\GuiPages.ps1`; Per-Monitor DPI awareness on the main form

**Safety**

- Every recursive delete now goes through `Test-SafeCleanupPath`, which refuses empty paths,
  drive roots, bare drive specs, `%USERPROFILE%`, `%SystemRoot%`, `%LOCALAPPDATA%`, Program Files,
  `C:\Users`, and known user document folders
- Self-update snapshots the current install, health-checks the new one, and rolls back automatically
  if the update fails to parse; the backup is kept at `%LOCALAPPDATA%\PC-Maintenance-Kit-backup`
- Self-update / installer purge `.ps1` files removed from the new release (stale `lib\` modules gone)
- Restart / Discord / refresh / clipboard buttons can no longer fire from a `DoEvents`-delivered
  click while a job is running (a reboot mid-DISM was previously possible)
- Unhandled UI exceptions are caught in-app instead of exiting with "failed to start"
- winget upgrades always confirm (removed unused skip switch)

**Fixes**

- Score and device caches are invalidated before the post-action refresh, so the score is never stale
- "Likely dual" RAM no longer scores as confirmed dual-channel
- Gaming status rows scroll instead of clipping; Cleanup buttons no longer overlap the last checkbox
- Progress status label no longer grows over the right-hand status text
- Settings: saves keep control-less and forward-compatible keys; a single bad value no longer
  silently aborts the whole restore
- `Compare-AppVersion` ignores `v` prefixes and prerelease suffixes instead of mis-ranking them
- Home / Updates / Repair GUI flag wiring goes through shared helpers

**Build / CI**

- `Build-Release.ps1` rejects a `-Version` that disagrees with `VERSION`, and now ships `Get.ps1`
  and `docs/` (release READMEs had broken screenshots)
- CI adds PSScriptAnalyzer, a timeout, concurrency control, artifact upload, signature verification,
  and tag-triggered GitHub Release publishing
- Test suite gained real behavioral coverage: cleanup path guards, an actual temp-tree clean,
  settings round-trip, and score invariants; `lib\*.ps1` parse checks are discovered from disk

## 5.2.6

- Progress bar: full redraw on resize so the cyan→violet fill stays a smooth gradient (no striped bands)

## 5.2.5

- Update check: if local version is newer than GitHub, say so (not "up to date")

## 5.2.4

Faster winget upgrades.

- List and upgrade with `--source winget` (skips slow msstore queries)
- One bulk `upgrade --all --silent` after temporarily pinning self-updaters
- Per-id fallback if pinning/bulk fails; temporary pins always removed

## 5.2.3

Third bugfix pass.

- Preview sizes no longer asks to clear caches before measuring; confirm only when running cleanup
- Reboot / update-check / Discord / RAM tip dialogs use `Show-UiMessageBox`
- Self-update checksum order matches `Get.ps1`
- Discord surgical edit replaces any existing `hardwareAcceleration` value

## 5.2.2

Second bugfix pass (Preview Run cleanup, Quit/CLI busy, UiModal, Get.ps1 errors, Discord surgical edit).

## 5.2.1

Bugfix release from full-project hunt.

## 5.2.0

Safety and integrity release.

## 5.1.6

- CI, SHA256 release checksums, and optional Authenticode signing
