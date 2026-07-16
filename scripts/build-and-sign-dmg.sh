#!/bin/bash
# Builds a Release .app (ad-hoc signed - there's no Apple Developer ID),
# packages it into a .dmg, and signs that .dmg with Sparkle's EdDSA key
# from the Keychain, ready to paste into appcast.xml.
#
# Requirements: Xcode command line tools, the "Private key for signing
# Sparkle updates" item in your login Keychain.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/Selene"
XCODEPROJ="$PROJECT_DIR/Selene.xcodeproj"
SCHEME="Selene"
INFO_PLIST="$PROJECT_DIR/Selene/App/Info.plist"
BUILD_DIR="$ROOT_DIR/build"
TOOLS_DIR="$ROOT_DIR/.sparkle-tools"

fail() { echo "error: $1" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild not found - install Xcode command line tools"
command -v /usr/libexec/PlistBuddy >/dev/null || fail "PlistBuddy not found"

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
echo "Version $SHORT_VERSION (build $BUILD_NUMBER)"

# --- 1. Build Release configuration (ad-hoc signed, no Developer ID) ---
echo "==> Building Release configuration"
rm -rf "$BUILD_DIR/DerivedData"
xcodebuild \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build || fail "xcodebuild failed"

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/Selene.app"
[ -d "$APP_PATH" ] || fail "Built app not found at $APP_PATH"

# --- 2. Package into a .dmg ---
echo "==> Packaging .dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/Selene-$SHORT_VERSION.dmg"
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "Selene" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null || fail "hdiutil failed"
rm -rf "$DMG_STAGING"

echo "Created $DMG_PATH"

# --- 3. Fetch (and cache) Sparkle's sign_update tool, matching the pinned SPM version ---
PACKAGE_RESOLVED=$(find "$XCODEPROJ" -iname "Package.resolved" | head -1)
[ -n "$PACKAGE_RESOLVED" ] || fail "Package.resolved not found - open the project in Xcode once to resolve packages"
SPARKLE_VERSION=$(/usr/bin/python3 -c "
import json
with open('$PACKAGE_RESOLVED') as f:
    data = json.load(f)
for pin in data['pins']:
    if pin['identity'] == 'sparkle':
        print(pin['state']['version'])
")
[ -n "$SPARKLE_VERSION" ] || fail "Could not determine pinned Sparkle version"
echo "==> Sparkle tools version $SPARKLE_VERSION"

SIGN_UPDATE="$TOOLS_DIR/$SPARKLE_VERSION/bin/sign_update"
if [ ! -x "$SIGN_UPDATE" ]; then
  echo "Downloading Sparkle $SPARKLE_VERSION command line tools"
  mkdir -p "$TOOLS_DIR/$SPARKLE_VERSION"
  TARBALL="$BUILD_DIR/Sparkle-$SPARKLE_VERSION.tar.xz"
  curl -fL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    -o "$TARBALL" || fail "Failed to download Sparkle tools tarball"
  tar -xf "$TARBALL" -C "$TOOLS_DIR/$SPARKLE_VERSION" bin/sign_update bin/generate_appcast || fail "Failed to extract sign_update"
  rm -f "$TARBALL"
fi

# --- 4. Sign the .dmg ---
# Locally this reads the key from the login Keychain. In CI, set
# SPARKLE_PRIVATE_KEY (the contents exported via `generate_keys -x`) instead -
# piped in via --ed-key-file -, since the older -s flag is deprecated and no
# longer works for keys generated in the newer (32-byte seed) format.
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "==> Signing with Sparkle EdDSA key from \$SPARKLE_PRIVATE_KEY"
  SIGN_OUTPUT=$(echo "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$DMG_PATH") || fail "sign_update failed - check that SPARKLE_PRIVATE_KEY is set correctly"
else
  echo "==> Signing with Sparkle EdDSA key from Keychain"
  SIGN_OUTPUT=$("$SIGN_UPDATE" "$DMG_PATH") || fail "sign_update failed - is the signing key in your login Keychain?"
fi
# sign_update prints a ready-to-paste `sparkle:edSignature="..." length="..."` string.
echo "$SIGN_OUTPUT"

ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')
DMG_LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
[ -n "$ED_SIGNATURE" ] && [ -n "$DMG_LENGTH" ] || fail "Could not parse edSignature/length from sign_update output"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "short_version=$SHORT_VERSION"
    echo "build_number=$BUILD_NUMBER"
    echo "dmg_path=$DMG_PATH"
    echo "ed_signature=$ED_SIGNATURE"
    echo "dmg_length=$DMG_LENGTH"
  } >> "$GITHUB_OUTPUT"
fi

DOWNLOAD_URL="https://github.com/Polonium-ch/Selene/releases/download/v$SHORT_VERSION/Selene-$SHORT_VERSION.dmg"

echo
echo "==> Done. Next steps:"
echo "  1. Create a GitHub Release tagged v$SHORT_VERSION and upload $DMG_PATH"
echo "  2. Make sure CHANGELOG.md has a '## [$SHORT_VERSION]' section (scripts/release.sh does this for you if you use it instead of running this script by hand)"
echo "  3. scripts/update-appcast.sh \"$SHORT_VERSION\" \"$BUILD_NUMBER\" \"$DMG_LENGTH\" \"$ED_SIGNATURE\" \"$DOWNLOAD_URL\""
echo "  4. Commit and push the updated appcast.xml to main"
