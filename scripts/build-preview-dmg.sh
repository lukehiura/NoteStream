#!/usr/bin/env bash
# Builds developer-preview zip (via build-preview-app-zip.sh) plus an ad-hoc–signed DMG.
# Same trust model as the zip: not Developer ID, not notarized (see README inside DMG).
set -euo pipefail

VERSION="${1:-dev}"

scripts/build-preview-app-zip.sh "$VERSION"

APP_PATH="build/preview/NoteStream.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

README_PATH="build/README-DEVELOPER-PREVIEW-DMG.txt"
cat > "$README_PATH" <<'TXT'
NoteStream Developer Preview

This DMG is ad-hoc signed only. It is not Developer ID signed and it is not notarized.

This is a developer preview. macOS may require you to approve the app in System Settings → Privacy & Security.

To install:
1. Open the DMG.
2. Drag NoteStream.app to Applications.
3. Open NoteStream.
4. If macOS blocks it, open System Settings → Privacy & Security and choose Open Anyway.

This preview is intended for testers and developers.
TXT

scripts/create-dmg.sh "$APP_PATH" "$VERSION" "$README_PATH"

echo "Developer preview zip and DMG are under build/"
