# Development

This document covers **local developer setup and daily commands** only. For **release, signing, and preview artifacts**, see `release.md`. For **stuck SwiftPM / locks / tests**, see `troubleshooting.md`.

## 1. Prerequisites

- macOS 14+
- Xcode command line tools (`xcodebuild -version`)
- Homebrew (used by `make bootstrap` / `Brewfile`)

## 2. Bootstrap

```bash
make bootstrap
```

Installs tools from the Brewfile, resolves packages, installs git hooks, and runs `make fast` (lints).

## 3. Daily commands

Makefile targets are the source of truth; these are the ones most people need:

| Task | Command |
|------|---------|
| Install tools and hooks | `make bootstrap` |
| Quick lints (no full `swift build` in `check.sh fast`) | `make fast` |
| Normal pre-PR / dev check (resolve, debug build, fast tests, `python3 -m py_compile` on diarize helper) | `make check` |
| Stricter check (adds release build + Python) | `make full-check` (alias `make ci-check`) |
| Run tests (fast, no coverage) | `make test-fast` |
| Coverage tests | `make test-coverage` |
| Full release gate (as for a tag) | `make release-verify` |
| Build (debug) | `make build` |
| Build release binary | `make release` |
| Run the app (local only) | `make run` |
| All linters + secrets + large-file report | `make quality` |
| Build preview zip | `make preview` or `make preview-version VERSION=x.y.z` |
| Build preview DMG (local) | `make preview-dmg` or `make preview-dmg-version VERSION=x.y.z` |

Run `make` with no target to see if your `make` lists targets, or read the [Makefile](../Makefile) comments.

**PR CI** (`.github/workflows/ci.yml`) runs **`scripts/check.sh dev`** (same as `make check`: lints, resolve, debug build, fast tests, Python tool compile; no release build; no coverage).

**Optional — stacked PRs:** [Aviator `av` CLI](https://docs.aviator.co/aviator-cli/) (`av init`, `av pr`) if you use stacked branches.

**Maintainer — GitHub hardening** (labels, optional branch/tag rules): `scripts/admin/gh-repo-harden.sh` (see `release.md`).

## 4. Testing strategy

- Default: `make test-fast` (XCTest, `--disable-swift-testing` — see [Makefile](../Makefile) and `scripts/run-swift-test-fast.sh`).
- Coverage: `make test-coverage` (nightly / manual; `.github/workflows/nightly-coverage.yml`).
- One test: `make test-one FILTER=NoteStreamCoreTests/AudioFrameTests/testAudioFrameDurationSecondsMono` (see `Makefile` for the `FILTER` pattern).

**Swift Testing vs XCTest:** This repo is wired for XCTest with `--disable-swift-testing` in scripts/Makefile. If you add Swift **Testing** to `Package.swift`, read `swift test --help` and adjust flags — do not mix harness assumptions.

## 5. Linting and formatting

- `make fast` — swift-format, SwiftLint (strict), markdownlint, shellcheck, actionlint, secrets scan.
- `make format` — apply swift-format in place.
- `make lint` / `make quality` — see [Makefile](../Makefile).

## 6. Git hooks

```bash
make hooks
```

- **pre-commit:** format/lint/secret checks (see `.githooks/`)
- **pre-push:** secrets + `make test-fast` (full `make fast` is for CI or before a PR as you prefer)

## 7. Local data and ignored files

Do not commit: audio, `Sessions/`, diagnostics, real transcripts, API keys, or tokens. See `SECURITY.md` and `.gitignore`.

## 8. See also

- `troubleshooting.md` — SwiftPM lock, permissions, common failures  
- `release.md` — preview ZIP/DMG, signing, tag workflow  
- `architecture.md` — module boundaries  
- `docs/tools/README.md` — external pyannote helper  

## Script map (non-exhaustive)

| Path | Role |
|------|------|
| `scripts/check.sh` | `fast` \| `dev` \| `ci` \| `full` \| `release` check ladder |
| `scripts/lib/script-lock.sh` | Serialize `check` / tests / packaging. Lock: **`$NOTESTREAM_LOCK_BASE/notestream-script.lock`** (default **`$REPO_ROOT/.lock/`**; not **`.build/`**). Re-entrant when **`NOTESTREAM_REPO_LOCK_HELD=1`**. Timeouts: **`NOTESTREAM_SCRIPT_LOCK_WAIT_SEC`** (default 30) |
| `scripts/lib/swiftpm.sh` | Time-bounded `swift` (env: `NOTESTREAM_SWIFTPM_TIMEOUT_SEC`, `NOTESTREAM_SWIFT_TEST_TIMEOUT_SEC`) |
| `scripts/diagnose-swiftpm-lock.sh` | Inspect tooling PIDs; optional `--kill <pid>` |
| `scripts/packaging/` | Preview app zip / DMG build |
