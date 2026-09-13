# Changelog

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
