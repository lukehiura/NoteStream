#!/usr/bin/env bash
set -euo pipefail

scripts/fast-check.sh

echo "Resolving package..."
swift package resolve

echo "Cleaning SwiftPM build..."
swift package clean

echo "Building debug..."
swift build

echo "Building release..."
swift build -c release

echo "Running tests with coverage..."
make test-coverage

echo "Checking Python helper tools..."
make python-tools-check

echo "CI check passed."
