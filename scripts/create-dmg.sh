#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: scripts/create-dmg.sh path/to/NoteStream.app 0.1.0}"
VERSION="${2:?Usage: scripts/create-dmg.sh path/to/NoteStream.app 0.1.0}"

DMG_PATH="build/NoteStream-${VERSION}.dmg"
STAGING_DIR="build/dmg-staging"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/NoteStream.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "NoteStream" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"

