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
if git grep -nE '(sk-[A-Za-z0-9_-]{20,}|OPENAI_API_KEY=|ANTHROPIC_API_KEY=|HF_TOKEN=|HUGGINGFACE_TOKEN=)' -- . ':!README.md' ':!docs/**' ':!.github/workflows/**' ':!scripts/**' ':!.githooks/**'; then
  echo "Possible API key or secret found."
  exit 1
fi

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

echo "Fast check passed."

