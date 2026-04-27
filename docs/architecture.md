# Architecture

This document is **conceptual and stable**. It does not replace `Package.swift` for exact target lists. For commands and workflows, see `development.md` and `release.md`.

## Layers

### NoteStreamCore

Domain models, ports (protocols), transcript logic, notes models, errors, diagnostics *contracts*, and pure helpers. **No** AppKit, SwiftUI, or WhisperKit.

### NoteStreamInfrastructure

Adapters: audio capture, file persistence, WhisperKit transcription, external process runners, HTTP LLM clients, diagnostics *implementations*. Depends on **Core** and WhisperKit (see `Package.swift`).

### NoteStreamApp

SwiftUI views, view models (`TranscriptionViewModel` and related), settings, export UI, playback, onboarding, and app-level wiring. Depends on **Core** and **Infrastructure**.

## Dependency rule

**App** → **Infrastructure** → **Core**  
**App** may use **Core** directly. **Core** must not import **App** or **Infrastructure**.

## Important flows (high level)

- **Recording:** ScreenCaptureKit / audio pipeline → chunking / VAD → `TranscriptionViewModel` → rolling transcript
- **Transcription:** WhisperKit (via infrastructure engine) → `TranscriptCoordinator` (commit / draft rules in Core)
- **Session persistence:** `FileSessionStore`, `SessionMetadata.schemaVersion` — bump schema and add `SessionPersistedMigration` when JSON evolves
- **AI notes / Q&A:** HTTP adapters + `LLMHTTPClient` stack; no raw secrets in logs (see `DiagnosticsRedactor`)
- **Speaker diarization:** optional external executable or debug fake (`DebugSpeakerDiarizer` in debug builds)

## Errors and logging

- Prefer `NoteStreamError` for user-visible failures.
- Do not log transcript text, prompts, or API keys. Use redaction/sanitization for persisted diagnostics.

## UI and concurrency

- Keep SwiftUI views thin; put policy in view models and Core.
- Long-running work must not block the main actor (transcription, I/O, network, LLM).

## Testing

- Adapters should have tests; persistence changes need migration tests when schema version changes.
