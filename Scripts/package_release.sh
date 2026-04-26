#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/CommandNest.xcodeproj"
SCHEME="CommandNest"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
STAGING="$ROOT_DIR/build/staging"
DIST="$ROOT_DIR/dist"
INFO_PLIST="$ROOT_DIR/CommandNest/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
ARCHIVE_NAME="CommandNest-${VERSION}-${BUILD_NUMBER}"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/CommandNest.app"
APP_STAGED="$STAGING/CommandNest.app"
ZIP_PATH="$DIST/${ARCHIVE_NAME}.zip"
CHECKSUM_PATH="$DIST/${ARCHIVE_NAME}.sha256"

echo "Building CommandNest ${VERSION} (${BUILD_NUMBER})..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  clean build

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Expected app not found at $APP_SOURCE" >&2
  exit 1
fi

mkdir -p "$DIST"
rm -rf "$STAGING" "$ZIP_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGING"
ditto --norsrc "$APP_SOURCE" "$APP_STAGED"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Signing with Developer ID identity: $CODESIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_STAGED"
else
  echo "No CODESIGN_IDENTITY set. Applying ad-hoc signature for local distribution."
  codesign --force --deep --options runtime --sign - "$APP_STAGED"
fi

codesign --verify --deep --strict "$APP_STAGED"
ditto -c -k --keepParent --norsrc "$APP_STAGED" "$ZIP_PATH"

(
  cd "$DIST"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "Created:"
echo "  $ZIP_PATH"
echo "  $CHECKSUM_PATH"
