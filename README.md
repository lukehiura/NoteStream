# NoteStream

NoteStream is a macOS app for recording, transcribing, reviewing, and exporting lecture or meeting notes locally.

## Status

Developer preview. Builds are ad-hoc signed and not notarized.

## Features

- System audio recording
- Local WhisperKit transcription
- Transcript editing and export
- AI notes through local or configured LLM providers
- Optional speaker diarization through external tools

## Requirements

- macOS 14+
- Xcode command line tools
- Homebrew for developer tooling

## Quick start

```bash
make bootstrap
make run
```

## Common commands

```bash
make fast
make check
make test-fast
make preview
make preview-dmg
```

See the [Makefile](Makefile) for additional targets.

## Docs map

| Need | Read |
|------|------|
| Run the app locally | [`docs/development.md`](docs/development.md) |
| Understand code structure | [`docs/architecture.md`](docs/architecture.md) |
| Fix stuck builds/tests | [`docs/troubleshooting.md`](docs/troubleshooting.md) |
| Cut a preview release | [`docs/release.md`](docs/release.md) |
| Validate a build manually | [`docs/manual-smoke-test.md`](docs/manual-smoke-test.md) |
| Configure pyannote diarization | [`docs/tools/README.md`](docs/tools/README.md) |

## Security

Do not commit recordings, transcripts, API keys, or local session data. See [`SECURITY.md`](SECURITY.md).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md).
