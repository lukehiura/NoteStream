#!/usr/bin/env bash
set -euo pipefail

# Diagnostic only: which SwiftPM/Xcode-related processes are active, and optional safe single-PID
# kill. Do not treat any path under .build/ as a stable public API. Prefer: inspect PID, then
# `swift package clean` if no active writer.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ $# -gt 0 && "$1" == "--kill" ]]; then
  target_pid="${2:-}"
  if [[ -z "$target_pid" ]]; then
    echo "Usage: scripts/diagnose-swiftpm-lock.sh --kill <pid>" >&2
    exit 2
  fi
  if ! kill -0 "$target_pid" 2>/dev/null; then
    echo "PID $target_pid is not running."
    exit 0
  fi
  command_out="$(ps -p "$target_pid" -o command= 2>/dev/null || true)"
  case "$command_out" in
    *swift* | *Swift* | *xctest* | *XCTest* | *sourcekit* | *xcodebuild* )
      echo "About to terminate PID $target_pid:"
      ps -p "$target_pid" -o pid=,ppid=,etime=,stat=,command= 2>/dev/null
      kill "$target_pid" || true
      sleep 3
      if kill -0 "$target_pid" 2>/dev/null; then
        echo "PID $target_pid did not exit after SIGTERM."
        echo "Use this only if you are sure it is stale:"
        echo "  kill -9 $target_pid"
        exit 1
      fi
      echo "Terminated PID $target_pid."
      ;;
    *)
      echo "Refusing to kill PID $target_pid because it does not look like SwiftPM/Xcode/test tooling." >&2
      echo "Command: $command_out" >&2
      exit 1
      ;;
  esac
  exit 0
fi

echo "SwiftPM lock diagnosis for $REPO_ROOT"
echo ""

echo "Matching Swift-related processes:"
# BSD pgrep on macOS does not print argv like GNU pgrep -af; use ps (not pgrep) for a portable listing.
# shellcheck disable=SC2009
ps -ax -o pid=,ppid=,etime=,command= 2>/dev/null \
  | grep -E 'swift|swift-build|swift-package|xctest|sourcekit|xcodebuild' \
  | grep -v grep \
  | head -60 || true

echo ""
echo "Processes with this repo path under .build (if lsof is available):"
if command -v lsof >/dev/null 2>&1; then
  lsof +D "$REPO_ROOT/.build" 2>/dev/null | head -80 || true
else
  echo "lsof not available."
fi

echo ""
echo "If SwiftPM printed a PID, inspect it:"
echo "  ps -p <pid> -o pid=,ppid=,etime=,stat=,command="
echo ""
echo "If it is clearly a stale Swift/Xcode tool process and you need to end it:"
echo "  scripts/diagnose-swiftpm-lock.sh --kill <pid>"
echo ""
echo "After terminating a stale process:"
echo "  swift package clean"
echo "  make test-fast"
echo ""
echo "Never blanket-kill all swift processes, delete internal workspace-state lock paths as routine policy, or use --ignore-lock as a default. Concurrent SwiftPM can corrupt .build; upstream added locking to prevent that."
echo ""
echo "Optional: separate scratch paths for parallel CI jobs, e.g. swift test --scratch-path .build/test-fast (see SwiftPM docs). For local work, use the repo script lock instead."
