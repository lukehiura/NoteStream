# Contributing to NoteStream

## Setup

```bash
make bootstrap
```

## Common commands

```bash
make fast
make check
make test
make run
```

## Running the app locally

```bash
make run
```

This starts the macOS app and keeps running until you quit NoteStream. Do not use `make run` in hooks or CI.

For automated checks, use:

```bash
make fast
make check
```

## Rules

- Do not commit recordings, transcripts, diagnostics, or local session folders.
- Do not commit API keys or Hugging Face tokens.
- Keep `NoteStreamCore` UI-free.
- Put macOS APIs and external adapters in `NoteStreamInfrastructure`.
- Keep SwiftUI views thin (compose UI; keep policy in view models / Core).
- Add tests for core logic and adapter contracts.
- Do not log transcript text, notes text, prompts, raw model responses, audio contents, or API keys.

## Before opening a PR

```bash
make check
```
