#!/usr/bin/env bash
set -euo pipefail

REPO="${COMMANDNEST_REPO:-vininhosts/CommandNest}"
ASSET="CommandNest-macOS.zip"
CHECKSUM_ASSET="CommandNest-macOS.sha256"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
TMP_DIR="$(mktemp -d)"
ZIP_PATH="$TMP_DIR/$ASSET"
CHECKSUM_PATH="$TMP_DIR/$CHECKSUM_ASSET"
APP_PATH="$TMP_DIR/CommandNest.app"
INSTALL_PATH="/Applications/CommandNest.app"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading CommandNest for macOS..."
curl -fL --progress-bar "$BASE_URL/$ASSET" -o "$ZIP_PATH"

if curl -fsL "$BASE_URL/$CHECKSUM_ASSET" -o "$CHECKSUM_PATH"; then
  echo "Verifying checksum..."
  (
    cd "$TMP_DIR"
    shasum -a 256 -c "$CHECKSUM_ASSET"
  )
fi

ditto -x -k "$ZIP_PATH" "$TMP_DIR"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Downloaded archive did not contain CommandNest.app." >&2
  exit 1
fi

echo "Installing to $INSTALL_PATH..."
if [[ -w "/Applications" ]]; then
  rm -rf "$INSTALL_PATH"
  ditto --norsrc "$APP_PATH" "$INSTALL_PATH"
else
  sudo rm -rf "$INSTALL_PATH"
  sudo ditto --norsrc "$APP_PATH" "$INSTALL_PATH"
fi

codesign --verify --deep --strict "$INSTALL_PATH"
open "$INSTALL_PATH"
echo "CommandNest installed and launched."
