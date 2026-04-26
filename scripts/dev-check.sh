#!/usr/bin/env bash
set -euo pipefail

scripts/fast-check.sh

echo "Resolving package..."
swift package resolve

echo "Cleaning SwiftPM build (drops stale test harness from cache or prior layouts)..."
swift package clean

echo "Building debug..."
swift build

echo "Building release..."
swift build -c release

echo "Running tests with coverage..."
# XCTest-only: avoid SPM importing toolchain Swift Testing (requires swift-testing package / _TestingInternals).
swift test --enable-code-coverage --disable-swift-testing

echo "Developer check passed."

