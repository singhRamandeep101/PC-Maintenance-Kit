# Changelog

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
