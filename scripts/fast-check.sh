#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$ROOT"
export REPO_ROOT
cd "$REPO_ROOT"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/script-lock.sh"
acquire_repo_lock

echo "Checking for private recording/session artifacts..."
forbidden="$(git ls-files | grep -Ei '(\.(caf|wav|m4a|mp3|flac|aiff)$|(^|/)Sessions(/|$)|(^|/)sessions(/|$)|(^|/)diagnostics\.jsonl$|(^|/)app\.jsonl$)' || true)"

if [ -n "$forbidden" ]; then
  echo "Forbidden private/local artifacts are committed:"
  echo "$forbidden"
  exit 1
fi

"$SCRIPT_DIR/check-secrets.sh"

echo "Running swift-format lint..."
swift-format lint --strict --recursive Sources Tests

echo "Running SwiftLint..."
swiftlint lint --strict

echo "Running Markdown lint..."
md_files=(README.md)
if [ -d docs ]; then
  while IFS= read -r -d '' f; do md_files+=("$f"); done < <(find docs -name '*.md' -print0)
fi
markdownlint "${md_files[@]}"

echo "Running ShellCheck..."
shopt -s nullglob
sc=(scripts/*.sh scripts/*/*.sh .githooks/*)
shellcheck "${sc[@]}"

echo "Running actionlint..."
actionlint

echo "Fast check passed."

