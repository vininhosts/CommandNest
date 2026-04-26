#!/usr/bin/env bash
set -euo pipefail

REPO="${COMMANDNEST_REPO:-vininhosts/CommandNest}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64 | amd64) RELEASE_ARCH="x64" ;;
  arm64 | aarch64) RELEASE_ARCH="arm64" ;;
  *)
    echo "Unsupported Linux architecture: $ARCH" >&2
    exit 1
    ;;
esac

ASSET="CommandNest-linux-${RELEASE_ARCH}.tar.gz"
CHECKSUM_ASSET="CommandNest-linux-${RELEASE_ARCH}.sha256"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
INSTALL_DIR="${COMMANDNEST_INSTALL_DIR:-$HOME/.local/opt/commandnest}"
BIN_DIR="${COMMANDNEST_BIN_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading CommandNest for Linux ${RELEASE_ARCH}..."
curl -fL --progress-bar "$BASE_URL/$ASSET" -o "$TMP_DIR/$ASSET"

if curl -fsL "$BASE_URL/$CHECKSUM_ASSET" -o "$TMP_DIR/$CHECKSUM_ASSET"; then
  echo "Verifying checksum..."
  (
    cd "$TMP_DIR"
    sha256sum -c "$CHECKSUM_ASSET"
  )
fi

tar -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR"
EXTRACTED_DIR="$TMP_DIR/CommandNest-linux-${RELEASE_ARCH}"
if [[ ! -x "$EXTRACTED_DIR/CommandNest" ]]; then
  echo "Downloaded archive did not contain the CommandNest executable." >&2
  exit 1
fi

echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"
mkdir -p "$(dirname "$INSTALL_DIR")" "$BIN_DIR" "$DESKTOP_DIR"
mv "$EXTRACTED_DIR" "$INSTALL_DIR"
ln -sfn "$INSTALL_DIR/CommandNest" "$BIN_DIR/commandnest"

cat > "$DESKTOP_DIR/commandnest.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=CommandNest
Comment=Desktop AI assistant powered by OpenRouter
Exec=$INSTALL_DIR/CommandNest
Terminal=false
Categories=Utility;Development;
StartupWMClass=CommandNest
DESKTOP

chmod +x "$DESKTOP_DIR/commandnest.desktop"
echo "CommandNest installed. Run it from your app launcher or with: commandnest"
