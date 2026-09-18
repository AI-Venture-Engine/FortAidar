#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

APP_PRODUCT="FortAidarApp"
BUNDLE_NAME="Fort Aidar"
BUNDLE_ID="ai.aiventureengine.FortAidar"
APP_VERSION="0.1.0"
APP_RELEASE_LABEL="0.1.0-preview"
MIN_SYSTEM_VERSION="14.0"
PACKAGE_CHANNEL="${FORTAIDAR_PACKAGE_CHANNEL:-preview}"
SIGNING_IDENTITY="${FORTAIDAR_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${FORTAIDAR_NOTARY_PROFILE:-}"
BUILD_ARCHS=(arm64 x86_64)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon/FortAidarIcon.icns"
DMG_ICON_SOURCE="$ROOT_DIR/Assets/AppIcon/FortAidarIcon.png"
STAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
BUILD_STAMP="${BUILD_STAMP:-$(date -u +"%Y%m%d%H%M%S")}"
if [[ ! "$BUILD_STAMP" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "BUILD_STAMP must be a numeric CFBundleVersion such as 20260918010926" >&2
  exit 2
fi
case "$PACKAGE_CHANNEL" in
  preview)
    ARTIFACT_BASENAME="FortAidar-preview-$STAMP"
    ;;
  distribution)
    ARTIFACT_BASENAME="FortAidar-$APP_VERSION-$STAMP"
    if [[ "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
      echo "FORTAIDAR_SIGNING_IDENTITY must name a Developer ID Application identity" >&2
      exit 2
    fi
    if [ -z "$NOTARY_PROFILE" ]; then
      echo "FORTAIDAR_NOTARY_PROFILE must name a notarytool Keychain profile" >&2
      exit 2
    fi
    ;;
  *)
    echo "FORTAIDAR_PACKAGE_CHANNEL must be preview or distribution" >&2
    exit 2
    ;;
esac

RELEASE_DIR="$ROOT_DIR/release/$ARTIFACT_BASENAME"
APP_BUNDLE="$RELEASE_DIR/$BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_PRODUCT"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ZIP_PATH="$ROOT_DIR/release/$ARTIFACT_BASENAME.zip"
DMG_PATH="$ROOT_DIR/release/$ARTIFACT_BASENAME.dmg"
NOTARY_RESULT_PATH="$ROOT_DIR/release/$ARTIFACT_BASENAME.notary.json"

apply_custom_file_icon() {
  local target_path="$1"
  local icon_png="$2"
  local icon_work="/private/tmp/cx1-fortaidar-dmgicon-$STAMP.png"

  cp "$icon_png" "$icon_work"
  /usr/bin/sips -i "$icon_work" >/dev/null
  cat "$icon_work/..namedfork/rsrc" > "$target_path/..namedfork/rsrc"
  /usr/bin/SetFile -a C "$target_path"
  rm -f "$icon_work"
}

mkdir -p "$APP_MACOS" "$APP_RESOURCES"

cd "$ROOT_DIR"
swift build -c release --arch "${BUILD_ARCHS[0]}" --arch "${BUILD_ARCHS[1]}" --product "$APP_PRODUCT"
BUILD_DIR="$(swift build -c release --arch "${BUILD_ARCHS[0]}" --arch "${BUILD_ARCHS[1]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_PRODUCT"
RESOURCE_BUNDLE="$BUILD_DIR/FortAidar_FortAidarApp.bundle"

for required_arch in "${BUILD_ARCHS[@]}"; do
  if ! /usr/bin/lipo -archs "$BUILD_BINARY" | /usr/bin/grep -qw "$required_arch"; then
    echo "missing required architecture: $required_arch" >&2
    exit 1
  fi
done

cp "$BUILD_BINARY" "$APP_BINARY"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi
cp "$ICON_SOURCE" "$APP_RESOURCES/FortAidarIcon.icns"
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
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_STAMP</string>
  <key>CFBundleIconFile</key>
  <string>FortAidarIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSFaceIDUsageDescription</key>
  <string>Fort Aidar uses biometric authentication to unlock and lock your local encrypted vault.</string>
</dict>
</plist>
PLIST

ln -s /Applications "$RELEASE_DIR/Applications"
cat >"$RELEASE_DIR/INSTALL.txt" <<INFO
Install Fort Aidar

1. Drag Fort Aidar.app onto the Applications shortcut in this window.
2. Eject this disk image.
3. Open Fort Aidar from Applications.

Version: $APP_VERSION
Release label: $APP_RELEASE_LABEL
Build: $BUILD_STAMP
Architecture: arm64 + x86_64
INFO
cp "$ICON_SOURCE" "$RELEASE_DIR/.VolumeIcon.icns"
if [ -x /usr/bin/SetFile ]; then
  /usr/bin/SetFile -a C "$RELEASE_DIR"
fi

if [ "$PACKAGE_CHANNEL" = "distribution" ]; then
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"
else
  /usr/bin/codesign --force --sign - "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$BUNDLE_NAME.app/Contents/MacOS/$APP_PRODUCT" > "$ROOT_DIR/release/$ARTIFACT_BASENAME.app.sha256"
)

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

/usr/bin/shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

/usr/bin/hdiutil create \
  -volname "Fort Aidar $BUILD_STAMP" \
  -srcfolder "$RELEASE_DIR" \
  -format UDZO \
  "$DMG_PATH"

apply_custom_file_icon "$DMG_PATH" "$DMG_ICON_SOURCE"

if [ "$PACKAGE_CHANNEL" = "distribution" ]; then
  /usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
  /usr/bin/xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --output-format json > "$NOTARY_RESULT_PATH"

  NOTARY_STATUS="$(/usr/bin/plutil -extract status raw -o - "$NOTARY_RESULT_PATH")"
  if [ "$NOTARY_STATUS" != "Accepted" ]; then
    echo "notarization status is $NOTARY_STATUS, expected Accepted" >&2
    exit 1
  fi

  /usr/bin/xcrun stapler staple "$DMG_PATH"
  /usr/bin/xcrun stapler validate "$DMG_PATH"
  /usr/sbin/spctl \
    --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$DMG_PATH"
fi

/usr/bin/shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

if [ ! -L "$RELEASE_DIR/Applications" ] || [ "$(readlink "$RELEASE_DIR/Applications")" != "/Applications" ]; then
  echo "DMG staging root is missing the Applications link" >&2
  exit 1
fi

/usr/bin/hdiutil verify "$DMG_PATH"

echo "$RELEASE_DIR"
echo "$ZIP_PATH"
echo "$DMG_PATH"
