# Contributing to NoteStream

## Before opening a PR

```bash
make check
```

For full local setup, targets, and CI behavior, see [`docs/development.md`](docs/development.md). For architecture, see [`docs/architecture.md`](docs/architecture.md). For release and signing, see [`docs/release.md`](docs/release.md).

## Code style

- **Swift:** match existing formatting (`make format` / `make fast`). `NoteStreamCore` stays free of AppKit and SwiftUI.
- **Adapters and I/O** live in `NoteStreamInfrastructure`.
- **SwiftUI** stays relatively thin; policy belongs in view models and Core.
- **Secrets / privacy:** do not log transcript text, prompts, or API keys. Do not commit recordings, session folders, or diagnostics.

## Tests

- Add or update tests for Core logic and infrastructure adapters.
- Use `make test-fast`; coverage when behavior warrants it (`make test-coverage`).

## PR checklist

- [ ] `make check` passes
- [ ] New behavior covered by tests where practical
- [ ] User-visible changes noted in `CHANGELOG.md`
- [ ] No secrets, recordings, or local artifacts in the branch

## Documentation

- **Setup / commands:** `docs/development.md`
- **Layering and flows:** `docs/architecture.md`
- **Releases and previews:** `docs/release.md`
- **Incident-style fixes (SwiftPM, etc.):** `docs/troubleshooting.md`
