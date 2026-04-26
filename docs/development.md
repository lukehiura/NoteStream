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

## SwiftPM tests: XCTest vs Swift Testing

SwiftPM can generate a test harness that imports the Swift **Testing** module. Whether you pass **`--disable-swift-testing`** to `swift test` depends on how this package is wired:

- **This repo lists `swift-testing` in `Package.swift` and tests use `@Test` / `#expect`:** run plain `swift test` (same as today on `main`). Do **not** pass `--disable-swift-testing`, or those tests will not run correctly.
- **Tests are XCTest-only and the `swift-testing` package is removed from `Package.swift`:** always pass **`--disable-swift-testing`** (CI, `Makefile`, `scripts/dev-check.sh`). Otherwise the harness may `import Testing` and fail with **missing `_TestingInternals`**, because the toolchain path does not match a standalone XCTest-only package.

If you change layout, run `swift package clean` once locally if you see a stale harness after toggling dependencies.

There is no `swift test --use-xctest` flag; see `swift test --help` for `--disable-swift-testing` and `--enable-xctest`.

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
