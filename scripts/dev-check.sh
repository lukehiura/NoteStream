#!/usr/bin/env bash
set -euo pipefail

scripts/fast-check.sh

echo "Resolving package..."
swift package resolve

echo "Building debug..."
swift build

echo "Running fast tests..."
make test-fast

echo "Developer check passed."
