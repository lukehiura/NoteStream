#!/usr/bin/env bash
# Coverage XCTest (used by scripts/check.sh release and make test-coverage).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT
cd "$REPO_ROOT"

# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/script-lock.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/swiftpm.sh"

acquire_repo_lock
swiftpm test --enable-code-coverage --disable-swift-testing
