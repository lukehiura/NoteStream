#!/usr/bin/env bash
# Diagnostic: list Swift source files with more than N non-empty lines. Does not fail CI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

min_lines="${1:-300}"

printf 'Swift files over %s lines (wc -l; informational only)\n' "$min_lines"
# shellcheck disable=SC2016
find Sources Tests -name '*.swift' -type f 2>/dev/null | while read -r f; do
  lines=$(wc -l <"$f" | tr -d ' ')
  if [ "$lines" -gt "$min_lines" ]; then
    printf '  %5s  %s\n' "$lines" "$f"
  fi
done | sort -nr -k1 || true

echo ""
echo "Use this to find candidates for splits; it is not a merge gate."
exit 0
