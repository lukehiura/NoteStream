# NoteStream release checklist

This repo is developed as a Swift Package. For end-user distribution, ship a **Developer ID signed + notarized** macOS app (DMG) via GitHub Releases.

## Before tagging

- [ ] `swift test`
- [ ] Build + run the Release app locally
- [ ] Run `docs/manual-smoke-test.md`
- [ ] Verify first-run setup wizard
- [ ] Verify Screen Recording permission flow
- [ ] Verify system audio capture (ScreenCaptureKit)
- [ ] Verify Stop & Transcribe (final cleanup pass)
- [ ] Verify import audio file
- [ ] Verify transcript save/load after relaunch
- [ ] Verify AI Notes disabled behavior (privacy default)
- [ ] Verify Local Ollama notes (if enabled)
- [ ] Verify OpenAI/Anthropic key storage in Keychain (if enabled)
- [ ] Verify export transcript Markdown
- [ ] Verify “delete audio after transcription” behavior
- [ ] Verify diagnostics export defaults (no transcript text, no API keys, no audio)
- [ ] Verify app launches after moving to `/Applications`
- [ ] Verify notarized DMG opens on another Mac

## Versioning

- [ ] Update app version (`CFBundleShortVersionString`)
- [ ] Update build number (`CFBundleVersion`)
- [ ] Update `CHANGELOG.md`
- [ ] Tag as `vX.Y.Z` (or `vX.Y.Z-beta.N`)

## Distribution

- [ ] Archive Release build (Developer ID)
- [ ] Notarize
- [ ] Staple notarization ticket
- [ ] Create DMG
- [ ] Notarize + staple DMG
- [ ] Upload DMG to GitHub Releases
