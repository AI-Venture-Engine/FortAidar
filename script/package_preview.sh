#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

APP_PRODUCT="FortAidarApp"
BUNDLE_NAME="Fort Aidar"
BUNDLE_ID="ai.aiventureengine.FortAidar"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
RELEASE_DIR="$ROOT_DIR/release/FortAidar-preview-$STAMP"
APP_BUNDLE="$RELEASE_DIR/$BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_PRODUCT"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ZIP_PATH="$ROOT_DIR/release/FortAidar-preview-$STAMP.zip"

mkdir -p "$APP_MACOS" "$APP_RESOURCES"

cd "$ROOT_DIR"
swift build -c release --product "$APP_PRODUCT"
BUILD_DIR="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_PRODUCT"
RESOURCE_BUNDLE="$BUILD_DIR/FortAidar_FortAidarApp.bundle"

cp "$BUILD_BINARY" "$APP_BINARY"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_PRODUCT</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSFaceIDUsageDescription</key>
  <string>Fort Aidar uses biometric authentication to unlock your local encrypted vault secret from Keychain.</string>
</dict>
</plist>
PLIST

cp "$ROOT_DIR/README.md" "$RELEASE_DIR/"
cp "$ROOT_DIR/PREVIEW_NOTES.md" "$RELEASE_DIR/"
cp "$ROOT_DIR/SECURITY_NOTES.md" "$RELEASE_DIR/"
cp "$ROOT_DIR/LICENSE" "$RELEASE_DIR/"

/usr/bin/codesign --force --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$BUNDLE_NAME.app/Contents/MacOS/$APP_PRODUCT" > CHECKSUMS.txt
)

(
  cd "$ROOT_DIR/release"
  /usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$(basename "$RELEASE_DIR")" "$ZIP_PATH"
)

/usr/bin/shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "$RELEASE_DIR"
echo "$ZIP_PATH"
