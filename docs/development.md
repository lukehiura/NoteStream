# Development

## Local setup

```bash
make bootstrap
```

### Stacked PRs (Aviator CLI, optional)

[Aviator `av`](https://github.com/aviator-co/av) sits on top of Git: it tracks branch parent/child relationships in `.git/av/av.db` so you can open **stacked** pull requests, restack after merges, and run `av sync` instead of hand-rebasing chains of branches. It uses the same GitHub token as **`gh`** when `gh` is installed and authenticated (`gh auth login`).

**One-time per clone** (after `git clone`):

```bash
av init
```

**Typical flow** (from `main`):

```bash
git switch main && git pull
av branch my-feature          # or: av commit -A -m "msg" --branch-name my-feature
# edit, then:
av commit -A -m "Describe change"   # restacks children; use -a/--all like git
av pr                               # create or update PR for current branch
av tree                             # show stack and PR links
```

After a parent PR merges, **`av sync`** fetches, restacks descendants onto `main`, and prompts about push and deleting merged local branches.

Branches you created with plain **`git switch -c`** before using `av` are not tracked until you run **`av adopt`** (optionally `--parent main`) so `av tree` includes them. If **`av commit`** prints *current branch is not adopted* after committing, the commit still recorded; adopt the branch once, then later **`av commit`** runs will restack children as usual.

Shell completion (zsh): `source <(av completion zsh)` (Homebrew installs completion under `/opt/homebrew/share/zsh/site-functions` for `av`).

Full reference: [Aviator CLI docs](https://docs.aviator.co/aviator-cli/).

## Daily workflow

```bash
make run
make fast
make test
```

To build the same **developer preview zip** CI publishes on GitHub Releases (ad-hoc–signed, not notarized):

```bash
make preview
```

Optional local **DMG** (not attached to GitHub Releases):

```bash
make preview-dmg
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

## SwiftPM tests: XCTest vs Swift Testing

SwiftPM can generate a test harness that imports the Swift **Testing** module. Whether you pass **`--disable-swift-testing`** to `swift test` depends on how the package is wired:

- **This repo (XCTest-only targets, no `swift-testing` in `Package.swift`):** always pass **`--disable-swift-testing`** in CI, `Makefile`, and `scripts/dev-check.sh`. Otherwise the harness may `import Testing` and fail with **missing `_TestingInternals`**, because the toolchain path does not match a standalone XCTest-only package.

- **`swift-testing` is listed in `Package.swift` and tests use `@Test` / `#expect`:** use plain **`swift test`** (do **not** pass `--disable-swift-testing`), or those tests will not run correctly.

If you change layout or toggle dependencies, run **`swift package clean`** once locally if you see a stale harness.

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
