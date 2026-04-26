# NoteStream release checklist

This repo ships as a Swift package. **Current distribution** is a **developer preview**: an ad-hoc–signed `NoteStream.app` shipped as a **zip** and a **DMG** on GitHub Releases (same trust model for both — not Developer ID, not notarized). **A future** path is Developer ID signing + notarization (see Apple’s [Developer ID](https://developer.apple.com/support/developer-id/) and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) documentation, and the checklist below).

## Developer preview release (current)

- [ ] `make check` passes
- [ ] `make preview-version VERSION=x.y.z` and/or `make preview-dmg-version VERSION=x.y.z` work locally, or trust CI after tagging
- [ ] `CHANGELOG.md` updated if you publish user-visible changes
- [ ] Tag as `vX.Y.Z` or `vX.Y.Z-prerelease` (e.g. `v0.1.0-beta.1`)
- [ ] Push the tag; confirm `.github/workflows/developer-preview-release.yml` completes
- [ ] GitHub Release shows `NoteStream-<version>-developer-preview.zip`, `NoteStream-<version>.dmg`, and `README-DEVELOPER-PREVIEW-DMG.txt`

On `main`, CI exposes the required check name **Swift checks** (configure in branch protection after it has run once).

Tag format must match semver-style `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH-prerelease` (for example `v0.1.0-beta.1`) so the release workflow validation passes.

## Before tagging (quality bar)

- [ ] `make check` (includes `make test` with CI-aligned flags)
- [ ] Build + run the app locally (from source or from the preview zip)
- [ ] Run `docs/manual-smoke-test.md` when making meaningful changes
- [ ] Verify first-run setup, Screen Recording permission, system audio capture, Stop & Transcribe, import audio, save/load sessions, exports, AI off by default, diagnostics export safety

## Versioning

- [ ] Version string matches the tag and release notes
- [ ] `CHANGELOG.md` (when applicable)
- [ ] Tag as `vX.Y.Z` (or pre-release as above)
