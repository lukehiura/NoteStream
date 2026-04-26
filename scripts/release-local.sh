#!/usr/bin/env bash
# Future path: requires Apple Developer Program membership, a committed Xcode app target,
# Developer ID signing, and notarization. Do not use for the current developer-preview
# distribution (see scripts/build-preview-app-zip.sh and docs/release-checklist.md).
set -euo pipefail

VERSION="${1:?Usage: scripts/release-local.sh 0.1.0}"
SCHEME="${SCHEME:-NoteStream}"

ARCHIVE_PATH="build/NoteStream.xcarchive"
EXPORT_PATH="build/export"
APP_PATH="$EXPORT_PATH/NoteStream.app"
ZIP_PATH="build/NoteStream.zip"
DMG_PATH="build/NoteStream-${VERSION}.dmg"

rm -rf build
mkdir -p build

echo "Running tests..."
swift test --disable-swift-testing

echo "Archiving..."
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "Exporting Developer ID app..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ExportOptions.plist

echo "Preparing notarization zip..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Notarizing app..."
: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD}"

xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

echo "Stapling app..."
xcrun stapler staple "$APP_PATH"

echo "Creating DMG..."
scripts/create-dmg.sh "$APP_PATH" "$VERSION"

echo "Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"

echo "Verifying..."
spctl --assess --type execute --verbose=4 "$APP_PATH"
spctl --assess --type open --verbose=4 "$DMG_PATH"

echo "Release artifact ready: $DMG_PATH"

