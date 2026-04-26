# NoteStream architecture notes

## Layering

- **NoteStreamCore**: Foundation-only domain types, protocols, and pure logic. No AppKit or SwiftUI.
- **NoteStreamInfrastructure**: File I/O, HTTP, processes, WhisperKit, and other OS or network adapters. Depends on Core.
- **NoteStreamApp**: SwiftUI, view models, and composition. Depends on Core and Infrastructure.

## Persistence

- Saved sessions use `SessionMetadata.schemaVersion` (see `SessionFileSchema.current`). When the JSON shape evolves, bump the schema and extend `SessionPersistedMigration`.
- `FileSessionStore` runs `SessionPersistedMigration.migrateLoadedSession` after decode so older `session.json` files keep working.

## Errors and diagnostics

- Prefer throwing `NoteStreamError` for user-visible failures instead of ad hoc `NSError`.
- Do not log transcript text, prompts, API keys, or raw LLM bodies. Use `DiagnosticsRedactor.sanitize` paths for persisted diagnostics; structured metadata must go through `DiagnosticsRedactor.redact`.

## UI

- Keep SwiftUI views as thin composition layers. Push branching and policy into `TranscriptionViewModel` or Core helpers.
- Long-running work must not block the main actor (transcription, network, file export, LLM calls).

## Testing

- Every external adapter should have a mock or fake in tests.
- Raise `SessionFileSchema` only with a migration path and tests for older files.

## Planned hardening

- Centralize cancellation tokens for recording, rolling transcription, notes generation, model preparation, and diagnostics refresh instead of ad hoc `Task {}` where feasible.
