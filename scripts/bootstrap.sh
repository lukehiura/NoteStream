#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT
cd "$REPO_ROOT"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/script-lock.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/swiftpm.sh"
acquire_repo_lock

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
swiftpm package resolve

echo "Installing git hooks..."
"$SCRIPT_DIR/install-git-hooks.sh"

echo "Running fast check..."
"$SCRIPT_DIR/check.sh" fast

echo "Bootstrap complete."

