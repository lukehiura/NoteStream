# Changelog

All notable **user-facing** or **contributor-obvious** changes are documented here. [Releases](https://github.com/lukehiura/NoteStream/releases) ship developer preview zips unless stated otherwise.

## [0.1.0-beta.4] - 2026-04-27

### Added

- App icon in the developer preview `NoteStream.app` bundle.

### Changed

- Repo script lock path is **`.lock/notestream-script.lock`** (not under **`.build/`**), so CI `.build` cache cannot restore a stale lock. **CI** runs **`scripts/check.sh dev`**, which includes fast checks, resolve, build, fast tests, and Python tool compile.
- Script lock cleanup on exit no longer uses a trap that referenced out-of-scope variables (reliable `EXIT` with **`cleanup_repo_lock`** and **`NOTESTREAM_REPO_LOCK_DIR`**).
- Documentation reorganized: single owner per topic; see `docs/development.md`, `docs/troubleshooting.md`, `docs/release.md`.
- Developer preview releases remain **zip-only** on GitHub; DMG is local (`make preview-dmg`).
- `DebugSpeakerDiarizer` is **DEBUG** builds only.

### Fixed

- External JSON adapter no longer blocks the task pool on certain CI `Process` timeout paths.

## [0.1.0-beta.3] - 2026-04-26

### Changed

- Preview release workflow installs tools needed for the same fast checks as local `make fast`.
