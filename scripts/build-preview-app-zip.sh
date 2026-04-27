#!/usr/bin/env bash
# Builds an ad-hoc–signed (unsigned) .app from the SwiftPM release binary and zips it.
# This is a developer preview artifact, not a Developer ID or notarized distribution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ICON_SRC="$REPO_ROOT/Packaging/AppIcon.icns"

VERSION="${1:-dev}"
APP_NAME="NoteStream"
EXECUTABLE_NAME="NoteStream"
SWIFTPM_EXECUTABLE_NAME="NoteStreamApp"
BUNDLE_ID="com.lukehiura.notestream"

BUILD_ROOT="build/preview"
APP_DIR="$BUILD_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="build/$APP_NAME-$VERSION-developer-preview.zip"

rm -rf "$BUILD_ROOT" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Building SwiftPM release executable..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="$BIN_DIR/$SWIFTPM_EXECUTABLE_NAME"

if [ ! -f "$BINARY_PATH" ]; then
  echo "Missing SwiftPM executable at $BINARY_PATH"
  exit 1
fi

echo "Creating unsigned .app bundle..."
cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

echo "Copying SwiftPM resource bundles..."
find "$BIN_DIR" -maxdepth 1 -name "*.bundle" -type d -exec cp -R {} "$RESOURCES_DIR/" \;

if [[ ! -f "$ICON_SRC" ]]; then
  echo "Missing app icon at $ICON_SRC (build Packaging/AppIcon.icns; see Packaging/)." >&2
  exit 1
fi
cp "$ICON_SRC" "$RESOURCES_DIR/"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>

    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>

    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>

    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>

    <key>CFBundleVersion</key>
    <string>1</string>

    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <key>NSMicrophoneUsageDescription</key>
    <string>NoteStream may need microphone access if you record microphone audio.</string>

    <key>NSScreenCaptureUsageDescription</key>
    <string>NoteStream needs Screen Recording access to capture system audio.</string>

    <key>NSDocumentsFolderUsageDescription</key>
    <string>NoteStream stores recordings, transcripts, notes, and diagnostics in your Documents folder.</string>

    <key>NSDownloadsFolderUsageDescription</key>
    <string>NoteStream can import or export files you choose from Downloads.</string>

    <key>NSDesktopFolderUsageDescription</key>
    <string>NoteStream can import or export files you choose from the Desktop.</string>
  </dict>
</plist>
PLIST

cat > "$BUILD_ROOT/README-DEVELOPER-PREVIEW.txt" <<'TXT'
NoteStream Developer Preview

This build is ad-hoc signed only (not Developer ID) and is not notarized.

To open it:
1. Unzip this file.
2. Move NoteStream.app to Applications (optional).
3. Try opening it.
4. If macOS blocks it, open System Settings → Privacy & Security and choose Open Anyway.

This preview is intended for testers and developers. A signed, notarized app may be offered later.
TXT

echo "Ad-hoc signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "Creating zip..."
(
  cd "$BUILD_ROOT"
  zip -r "../../$ZIP_PATH" "$APP_NAME.app" "README-DEVELOPER-PREVIEW.txt"
)

echo "Created $ZIP_PATH"
