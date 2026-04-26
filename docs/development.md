# Development

## Local setup

```bash
make bootstrap
```

## Daily workflow

```bash
make run
make fast
make test
```

## Full verification

```bash
make check
```

## Git hooks

Install hooks:

```bash
make hooks
```

Hooks live in `.githooks/`.

- `pre-commit`: fast formatting, linting, secret checks, and artifact checks
- `pre-push`: full local verification

## Sensitive files

Never commit:

- audio files
- session folders
- diagnostics logs
- transcripts from real users
- notes from real users
- API keys
- Hugging Face tokens
