# NoteStream release checklist

This repo ships as a Swift package. **Current distribution** is a **developer preview** (unsigned, ad-hoc–signed app in a zip, attached to GitHub Releases). **A future** path is a Developer ID–signed, notarized macOS app (and optionally a DMG) once an Apple Developer account is available.

## Developer preview release (current)

- [ ] `make check` passes
- [ ] `make preview-version VERSION=x.y.z` works locally, or trust CI after tagging
- [ ] `CHANGELOG.md` updated if you publish user-visible changes
- [ ] Tag as `vX.Y.Z` or `vX.Y.Z-prerelease` (e.g. `v0.1.0-beta.1`)
- [ ] Push the tag; confirm `.github/workflows/developer-preview-release.yml` completes
- [ ] GitHub Release shows `NoteStream-<version>-developer-preview.zip`

On `main`, CI exposes the required check name **Swift checks** (configure in branch protection after it has run once).

Tag format must match semver-style `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH-prerelease` (for example `v0.1.0-beta.1`) so the release workflow validation passes.

## Future: notarized macOS release

Requires an **Apple Developer Program** membership, a **committed Xcode project** (or app target) with a shared **NoteStream** scheme, and secrets/certs configured for CI or local `scripts/release-local.sh`.

- [ ] `ExportOptions.plist` has a real `teamID` (not a placeholder)
- [ ] `scripts/release-local.sh` or CI produces a notarized app/DMG
- [ ] Test opening the artifact on another Mac; verify Screen Recording and first-run flow

## Before tagging (quality bar)

- [ ] `make check` (includes `make test` with CI-aligned flags)
- [ ] Build + run the app locally (from source or from the preview zip)
- [ ] Run `docs/manual-smoke-test.md` when making meaningful changes
- [ ] Verify first-run setup, Screen Recording permission, system audio capture, Stop & Transcribe, import audio, save/load sessions, exports, AI off by default, diagnostics export safety

## Versioning

- [ ] Version string matches the tag and release notes
- [ ] `CHANGELOG.md` (when applicable)
- [ ] Tag as `vX.Y.Z` (or pre-release as above)
