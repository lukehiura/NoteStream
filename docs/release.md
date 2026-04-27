# Release

This document owns **distribution trust, preview artifacts, and release gates**. For local development, see `development.md`. For manual validation steps, see `manual-smoke-test.md` (linked below; not duplicated here).

## Artifact types

| Artifact | Command | Published? | Signing |
|----------|---------|------------|---------|
| Developer preview ZIP | `make preview-version VERSION=x.y.z` (or `make preview` for `dev`) | GitHub Releases (on version tag) | Ad-hoc only |
| Local preview DMG | `make preview-dmg-version VERSION=x.y.z` | Local only | Ad-hoc only |
| Future public release | TBD | TBD | Developer ID + notarization (goal) |

ZIPs attached to GitHub Releases are **ZIP only**; DMG is Makefile-only.

## Developer preview warning

Developer preview builds are **ad-hoc signed only**. They are **not** Developer ID signed and **not** notarized. macOS may require approval under **System Settings → Privacy & Security** (e.g. Open Anyway).

Apple’s documentation on [Developer ID](https://developer.apple.com/support/developer-id/) and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) applies when you move beyond ad-hoc preview distribution.

## Release gate

Before tagging a developer preview:

```bash
make release-verify
```

Stricter local options: `make full-check` (alias `make ci-check`), or `make check` for a lighter pass. PR CI is a subset of these (see `development.md`).

## Checklist (tagged developer preview)

- [ ] `make check` passes; use `make release-verify` to mirror the tag workflow (clean + coverage + Python tools)
- [ ] `CHANGELOG.md` updated for user-visible changes
- [ ] Tag `vX.Y.Z` or `vX.Y.Z-prerelease` (e.g. `v0.1.0-beta.1`) — format must satisfy `.github/workflows/developer-preview-release.yml`
- [ ] Push tag; confirm **Developer Preview Release** workflow completes; GitHub Release contains `NoteStream-<version>-developer-preview.zip`
- [ ] Optional: `make preview-version VERSION=x.y.z` or DMG locally

**Before tagging (quality bar):** run the app, and when making meaningful changes follow `manual-smoke-test.md`.

## Manual validation

Use the procedural checklist in [`manual-smoke-test.md`](manual-smoke-test.md).

## Generated README text in ZIP/DMG

Packaging scripts embed a **short** notice in `README-DEVELOPER-PREVIEW.txt` (zip) and `README-DEVELOPER-PREVIEW-DMG.txt` (DMG) pointing here for full policy. Wording in GitHub Release notes is kept similarly short; **this file** is canonical.

## Maintainer: GitHub settings

Optional repo labels, branch protection, and tag rules: `scripts/admin/gh-repo-harden.sh` (see comments in that script; requires `gh auth login`).
