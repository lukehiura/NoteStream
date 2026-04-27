#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT
cd "$REPO_ROOT"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/script-lock.sh"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/swiftpm.sh"

usage() {
  echo "Usage: $0 {fast|dev|ci|full|release}" >&2
  exit 2
}

[ -n "$MODE" ] || usage

acquire_repo_lock

case "$MODE" in
  fast)
    section "Fast check"
    "$SCRIPT_DIR/fast-check.sh"
    ;;

  dev)
    section "Fast check"
    "$SCRIPT_DIR/fast-check.sh"

    section "Resolve"
    swiftpm package resolve

    section "Build debug"
    swiftpm build

    section "Fast tests"
    swiftpm test --disable-swift-testing

    section "Python tools"
    python3 -m py_compile docs/tools/notestream-diarize-pyannote.py

    echo "Developer check passed."
    ;;

  ci|full)
    section "Fast check"
    "$SCRIPT_DIR/fast-check.sh"

    section "Resolve"
    swiftpm package resolve

    section "Build debug"
    swiftpm build

    section "Build release"
    swiftpm build -c release

    section "Fast tests"
    swiftpm test --disable-swift-testing

    section "Python tools"
    python3 -m py_compile docs/tools/notestream-diarize-pyannote.py

    echo "Full check passed."
    ;;

  release)
    section "Fast check"
    "$SCRIPT_DIR/fast-check.sh"

    section "Resolve"
    swiftpm package resolve

    section "Clean SwiftPM build"
    swiftpm package clean

    section "Build debug"
    swiftpm build

    section "Build release"
    swiftpm build -c release

    section "Tests with coverage"
    swiftpm test --enable-code-coverage --disable-swift-testing

    section "Python tools"
    python3 -m py_compile docs/tools/notestream-diarize-pyannote.py

    echo "Release verify passed."
    ;;

  *)
    usage
    ;;
esac

