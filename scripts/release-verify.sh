#!/usr/bin/env bash
# Pre–developer-preview tag gate: lint, clean (fresh SwiftPM test harness), debug + release
# builds, tests with coverage, Python helpers.
set -euo pipefail

section() {
  echo ""
  echo "=============================="
  echo "$1"
  echo "=============================="
}

section "Fast check"
scripts/fast-check.sh

section "Resolve"
swift package resolve

section "Clean SwiftPM build"
swift package clean

section "Build debug"
swift build

section "Build release"
swift build -c release

section "Tests with coverage"
make test-coverage

section "Python tools"
make python-tools-check

section "Release verify passed"
