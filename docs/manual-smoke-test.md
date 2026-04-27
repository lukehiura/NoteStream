# Manual smoke test

Procedural validation before a significant release. For signing and tag process, see `release.md`. For dev setup, see `development.md`.

## Recording

- [ ] Launch app
- [ ] Grant Screen Recording (and any other) permissions as prompted
- [ ] Start system-audio recording; confirm audio path works
- [ ] Stop; confirm session saves and transcript appears

## File import

- [ ] Import a short audio file; confirm transcript and sidebar session

## Persistence

- [ ] Quit app
- [ ] Relaunch app
- [ ] Previous session(s) still present

## Export

- [ ] Export Markdown
- [ ] Export plain text
- [ ] Export SRT
- [ ] Export WebVTT

## AI notes (if you use them)

- [ ] Generate or refresh notes
- [ ] Ask a recording-scoped question (if enabled)
- [ ] Induce a provider error once; message is safe and recoverable

## Speaker diarization (if you use it)

- [ ] Debug diarizer path works in DEBUG, or
- [ ] External diarizer misconfiguration shows a clear error (no crash)
