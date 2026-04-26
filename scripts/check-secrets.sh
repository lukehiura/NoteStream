#!/usr/bin/env bash
set -euo pipefail

echo "Checking for obvious API keys..."

# NOTE: Split env var names so this script does not self-match when scanned.
patterns=(
  'sk-[A-Za-z0-9_-]{20,}'
  'OPENAI_''API_KEY='
  'ANTHROPIC_''API_KEY='
  'HF_''TOKEN='
  'HUGGINGFACE_''TOKEN='
  'HUGGING_''FACE_HUB_TOKEN='
)

pattern="$(IFS='|'; echo "${patterns[*]}")"

if git grep -nE "$pattern" -- \
  . \
  ':!README.md' \
  ':!docs/**' \
  ':!.github/workflows/**' \
  ':!scripts/check-secrets.sh' \
  ':!.githooks/**'
then
  echo "Possible API key or secret found."
  exit 1
fi

echo "Secret check passed."
