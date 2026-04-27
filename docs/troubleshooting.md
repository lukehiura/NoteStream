# Troubleshooting

This document covers incident-style fixes. For day-to-day setup, see `development.md`. For release and signing, see `release.md`.

## SwiftPM appears stuck on `.build`

**Symptom:**

```text
Another instance of SwiftPM ... is already running using '.build'
```

**Cause:** Another SwiftPM process, **SourceKit-LSP**, Xcode, an IDE, or a test run is holding the scratch-directory lock. SwiftPM uses this lock so concurrent commands do not corrupt the build arena.

**Check:**

```bash
./scripts/diagnose-swiftpm-lock.sh
```

Or list likely processes:

```bash
pgrep -af "swift|swift-build|swift-package|xctest|sourcekit-lsp"
```

**Recovery:**

1. If SwiftPM printed a **PID**, inspect it: `ps -p <pid> -o pid=,ppid=,etime=,stat=,command=`
2. If that process is **clearly stale** and is Swift/Xcode tooling, you may use `./scripts/diagnose-swiftpm-lock.sh --kill <pid>` (or terminate it yourself), then `swift package clean` and retry `make test-fast`.
3. If nothing should be using the tree, `swift package clean` (or, when fully idle, remove `.build`).

Do **not** treat **`workspace-state.json`**, a specific path under **`.build`**, or ad-hoc `rm` of internal lock files as a stable, supported fix — those are SwiftPM internals. Prefer process identification, then `swift package clean`.

**Repo script lock:** Local scripts use `scripts/lib/script-lock.sh` (lock under **`.lock/`**, not **`.build/`**, so SwiftPM’s cache and this mutex never share a path). Details: `docs/development.md` and `scripts/lib/swiftpm.sh` / `script-lock.sh` comments.

**Timeouts:** `scripts/lib/swiftpm.sh` caps wall time for `swift` invocations; override with `NOTESTREAM_SWIFTPM_TIMEOUT_SEC` and `NOTESTREAM_SWIFT_TEST_TIMEOUT_SEC` (see `development.md`).

**Do not** use `--ignore-lock` as a normal workflow; it exists for emergencies only.

## Tests / imports

- This package runs XCTest with `swift test --disable-swift-testing` (see `Makefile` and `scripts/run-swift-test-fast.sh`). A harness that imports Swift **Testing** without that dependency in `Package.swift` can fail; use the Makefile targets, not ad hoc `swift test`, unless you know the package layout.

## Permissions and capture

- **Screen Recording** is required for system audio. Grant it, restart the app if macOS requires it, and confirm audio is actually playing.
- Stuck **ScreenCaptureKit** capture: quit the app, recheck permissions, or restart the Mac if the system capture stack is wedged (see Diagnostics in the app).

## AI and models

- **Ollama:** app must be running; `curl http://localhost:11434/api/tags` should work; pull the model you selected.
- **Cloud providers:** key must be stored in Keychain from Settings; check provider errors in the UI.

## Still stuck?

Open an issue with steps, NoteStream and macOS versions, and (if relevant) redacted diagnostics — not raw recordings, transcripts, or keys.
