#!/usr/bin/env bash
set -euo pipefail

echo "Checking for private recording/session artifacts..."
forbidden="$(git ls-files | grep -Ei '(\.(caf|wav|m4a|mp3|flac|aiff)$|(^|/)Sessions(/|$)|(^|/)sessions(/|$)|(^|/)diagnostics\.jsonl$|(^|/)app\.jsonl$)' || true)"

if [ -n "$forbidden" ]; then
  echo "Forbidden private/local artifacts are committed:"
  echo "$forbidden"
  exit 1
fi

echo "Checking for obvious API keys..."
scripts/check-secrets.sh

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
shellcheck scripts/*.sh .githooks/*

echo "Running actionlint..."
actionlint

echo "Fast check passed."

