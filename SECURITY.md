# Security

## Supported versions

Security-sensitive reports should reference the **latest developer preview** (see [Releases](https://github.com/lukehiura/NoteStream/releases)) or your **local build** from `main` at the time of the report. There is no separate long-term support line yet.

## Reporting a vulnerability

Do not use public issues for sensitive reports.

Email: **YOUR_SECURITY_EMAIL** (replace with a monitored address before publishing widely)

Include:

- NoteStream version (tag or commit)
- macOS version
- Steps to reproduce
- Whether recordings, transcripts, API keys, Hugging Face tokens, or diagnostics are involved

## Sensitive data and local use

- Do not commit **recordings**, **transcripts**, **API keys**, **tokens**, **session data**, or **diagnostics** to the repository or public issues.
- The app stores sessions under `~/Documents/NoteStream/` by default. Treat that as **local, user-controlled** data; follow platform guidance for full-disk encryption and backups.
- **Cloud LLM** providers receive transcript (or prompt) text you send when you use those features; use **local** models (e.g. Ollama) if you need to avoid sending text off-device.

## General

Read [`README.md`](README.md) and [`docs/development.md`](docs/development.md) for what belongs in git vs. on disk only.
