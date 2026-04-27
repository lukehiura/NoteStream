#!/usr/bin/env bash
# Stage NoteStream.app (+ optional readme) and wrap in a compressed disk image.
# Used by developer-preview DMG builds (packaging/build-preview-dmg.sh).
set -euo pipefail

APP_PATH="${1:?Usage: scripts/packaging/create-dmg.sh path/to/NoteStream.app 0.1.0}"
VERSION="${2:?Usage: scripts/packaging/create-dmg.sh path/to/NoteStream.app 0.1.0}"
README_EXTRA="${3:-}"

DMG_PATH="build/NoteStream-${VERSION}.dmg"
STAGING_DIR="build/dmg-staging-${VERSION}"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/NoteStream.app"
ln -s /Applications "$STAGING_DIR/Applications"

if [ -n "$README_EXTRA" ] && [ -f "$README_EXTRA" ]; then
  cp "$README_EXTRA" "$STAGING_DIR/"
fi

hdiutil create \
  -volname "NoteStream ${VERSION}" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"

