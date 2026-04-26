#!/usr/bin/env bash
set -euo pipefail

echo "Checking Xcode command line tools..."
xcodebuild -version >/dev/null

echo "Installing Homebrew tools from Brewfile..."
if command -v brew >/dev/null 2>&1; then
  brew bundle
else
  echo "Homebrew is not installed. Install it from https://brew.sh, then rerun this script."
  exit 1
fi

echo "Resolving Swift package dependencies..."
swift package resolve

echo "Installing git hooks..."
scripts/install-git-hooks.sh

echo "Running fast check..."
scripts/fast-check.sh

echo "Bootstrap complete."

