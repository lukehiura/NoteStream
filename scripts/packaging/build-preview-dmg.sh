#!/usr/bin/env bash
# Builds developer-preview zip (via build-preview-app-zip.sh) plus an ad-hoc–signed DMG.
# Same trust model as the zip: not Developer ID, not notarized (canonical: docs/release.md).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export REPO_ROOT
cd "$REPO_ROOT"

# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/script-lock.sh"
acquire_repo_lock

VERSION="${1:-dev}"

"$SCRIPT_DIR/build-preview-app-zip.sh" "$VERSION"

APP_PATH="build/preview/NoteStream.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

README_PATH="build/README-DEVELOPER-PREVIEW-DMG.txt"
cat > "$README_PATH" <<'TXT'
NoteStream — developer preview (ad-hoc signed; not notarized).

For full policy and install expectations, see docs/release.md in the repository, or
https://github.com/lukehiura/NoteStream/blob/main/docs/release.md

To install: open the DMG, drag NoteStream.app to Applications, then open. If macOS blocks the app,
use System Settings → Privacy & Security (Open Anyway).
TXT

"$SCRIPT_DIR/create-dmg.sh" "$APP_PATH" "$VERSION" "$README_PATH"

echo "Developer preview zip and DMG are under build/"
