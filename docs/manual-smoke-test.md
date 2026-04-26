# Manual smoke test (Phase 2)

Run these before adding rolling/live transcription.

## Local quality gate

```bash
swift package resolve
swift build
swift test
swift-format lint --recursive Sources Tests
```

## File transcription flow

1. Open app
2. Prepare `base.en`
3. Drag in a short `.m4a` or `.mp3`
4. Confirm transcript appears
5. Confirm session appears in sidebar
6. Quit app
7. Reopen app
8. Confirm session reloads
9. Copy transcript
10. Save Markdown

## Recording flow

1. Click Start Recording
2. Grant Screen Recording permission
3. Restart app if macOS requires it
4. Start Recording again
5. Play 10–20 seconds of audio (YouTube is fine)
6. Click Stop & Transcribe
7. Confirm `audio.caf` exists
8. Open `audio.caf` in QuickTime
9. Confirm it is audible
10. Confirm transcript appears
11. Quit and reopen app
12. Confirm recorded session reloads
