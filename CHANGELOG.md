# Changelog

All notable changes to this project are documented here. Releases are [developer preview](https://github.com/lukehiura/NoteStream/releases) zips unless stated otherwise.

## [0.1.0-beta.4] - 2026-04-27

### Added

- App icon for the developer preview `NoteStream.app` bundle.

### Changed

- Refactored transcription-related infrastructure: shared external-process runner (timeout, concurrent stdout/stderr), shared LLM HTTP client / endpoints / response parsing for summarization and recording Q&A.
- GitHub developer preview releases ship a **zip only**; DMG remains available via `make preview-dmg` locally.
- `DebugSpeakerDiarizer` is available only in **DEBUG** builds.
- Lighter local checks: `make test` defaults to fast XCTest without coverage; `scripts/ci-check.sh` for CI and tagged releases; quieter CI builds (no `swift -v` spam).

### Fixed

- External JSON adapter timeout behavior on constrained CI runners (avoid blocking the cooperative pool while waiting on `Process`).

## [0.1.0-beta.3] - 2026-04-26

### Changed

- Preview release workflow installs ShellCheck and actionlint for parity with local checks.
