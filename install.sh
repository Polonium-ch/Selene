#!/bin/bash
# Downloads the latest Selene release, installs it to /Applications, and
# clears the Gatekeeper quarantine flag (Selene isn't notarized by Apple -
# there's no paid Developer ID behind this project).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Polonium-ch/Selene/main/install.sh | bash
set -euo pipefail

REPO="Polonium-ch/Selene"
APP_NAME="Selene.app"
INSTALL_DIR="/Applications"

fail() { echo "error: $1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "Selene only runs on macOS"
command -v curl >/dev/null || fail "curl not found"
command -v hdiutil >/dev/null || fail "hdiutil not found"

echo "==> Looking up the latest release"
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest") \
  || fail "Couldn't reach GitHub"

VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
DMG_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.dmg"' | head -1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')
[ -n "$DMG_URL" ] || fail "No .dmg found in the latest release"
echo "==> Found $VERSION"

TMP_DIR=$(mktemp -d)
MOUNT_POINT="$TMP_DIR/mnt"
cleanup() {
  hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Downloading $DMG_URL"
DMG_PATH="$TMP_DIR/Selene.dmg"
curl -fL --progress-bar "$DMG_URL" -o "$DMG_PATH" || fail "Download failed"

echo "==> Mounting the disk image"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet \
  || fail "Failed to mount the .dmg"

[ -d "$MOUNT_POINT/$APP_NAME" ] || fail "Couldn't find $APP_NAME inside the disk image"

if pgrep -x "Selene" >/dev/null 2>&1; then
  echo "==> Quitting the running copy of Selene"
  osascript -e 'quit app "Selene"' >/dev/null 2>&1 || true
  sleep 1
fi

if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
  echo "==> Removing the previous install"
  rm -rf "$INSTALL_DIR/$APP_NAME"
fi

echo "==> Installing to $INSTALL_DIR"
cp -R "$MOUNT_POINT/$APP_NAME" "$INSTALL_DIR/" \
  || fail "Copy failed - check permissions on $INSTALL_DIR"

hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true

echo "==> Clearing the quarantine flag"
xattr -cr "$INSTALL_DIR/$APP_NAME"

echo
echo "Selene $VERSION installed to $INSTALL_DIR/$APP_NAME"
echo "Open it from Launchpad or Spotlight."
