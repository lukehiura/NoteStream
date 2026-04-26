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

`make fast` runs `swift-format`, SwiftLint, Markdownlint, ShellCheck (`scripts/*.sh` and `.githooks/*`), and actionlint (`.github/workflows/*.yml`). Install those tools with Homebrew (`Brewfile` includes them) or run `make bootstrap`.

For lint without building or testing:

```bash
make quality
```

Tests run with **`swift test --disable-swift-testing`** (see `Makefile` and `scripts/dev-check.sh`) so SwiftPM does not generate a harness that imports toolchain Swift Testing while this package uses XCTest-only targets.

## Git hooks

Install hooks:

```bash
make hooks
```

Hooks live in `.githooks/`.

- `pre-commit`: fast formatting, linting, secret checks, and artifact checks
- `pre-push`: full local verification

## GitHub repo hardening (maintainers)

After `gh auth login`, you can apply default labels, read-only Actions workflow permissions, and optional branch/tag rules from the repo root:

```bash
chmod +x scripts/gh-repo-harden.sh
./scripts/gh-repo-harden.sh
```

After CI has reported the required check **Swift checks** at least once on `main`, enable branch protection:

```bash
APPLY_BRANCH_PROTECTION=1 ./scripts/gh-repo-harden.sh
```

Optional tag protection ruleset (requires GitHub rulesets support for the repo):

```bash
APPLY_TAG_RULESET=1 ./scripts/gh-repo-harden.sh
```

If you are the only maintainer and required reviews block merges, use `GH_REQUIRED_REVIEW_COUNT=0` when applying branch protection.

## Sensitive files

Never commit:

- audio files
- session folders
- diagnostics logs
- transcripts from real users
- notes from real users
- API keys
- Hugging Face tokens
