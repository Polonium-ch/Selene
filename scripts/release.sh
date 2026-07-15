#!/bin/bash
# Bumps the app version, commits, and pushes a tag - which triggers
# .github/workflows/release.yml to build, sign, and publish the release.
#
# Usage: scripts/release.sh <short-version> [build-number]
# Example: scripts/release.sh 0.1.2
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Selene/Selene/App/Info.plist"

fail() { echo "error: $1" >&2; exit 1; }

[ $# -ge 1 ] || fail "usage: $0 <short-version> [build-number]"
SHORT_VERSION="$1"

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
[ "$SHORT_VERSION" != "$CURRENT_VERSION" ] || fail "$SHORT_VERSION is already the current version"

CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
BUILD_NUMBER="${2:-$((CURRENT_BUILD + 1))}"

git -C "$ROOT_DIR" diff --quiet && git -C "$ROOT_DIR" diff --cached --quiet \
  || fail "working tree has uncommitted changes - commit or stash them first"

TAG="v$SHORT_VERSION"
git -C "$ROOT_DIR" rev-parse "$TAG" >/dev/null 2>&1 && fail "tag $TAG already exists"

echo "==> Bumping $CURRENT_VERSION (build $CURRENT_BUILD) -> $SHORT_VERSION (build $BUILD_NUMBER)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

git -C "$ROOT_DIR" add "$INFO_PLIST"
git -C "$ROOT_DIR" commit -m "Bump version to $SHORT_VERSION"
git -C "$ROOT_DIR" push origin HEAD

git -C "$ROOT_DIR" tag "$TAG"
git -C "$ROOT_DIR" push origin "$TAG"

echo
echo "==> Pushed $TAG - the Release workflow should be starting now:"
echo "    https://github.com/Polonium-ch/Selene/actions"
