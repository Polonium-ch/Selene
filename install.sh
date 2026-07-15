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

# Brand color #174d77, plus lighter tints for contrast on dark terminals
if [ -t 1 ]; then
  BASE=$'\033[38;2;23;77;119m'
  MID=$'\033[38;2;81;122;153m'
  LIGHT=$'\033[38;2;127;157;180m'
  PALE=$'\033[38;2;174;193;207m'
  BOLD=$(tput bold); DIM=$(tput dim); RESET=$(tput sgr0)
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
else
  BASE=""; MID=""; LIGHT=""; PALE=""
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""
fi

step()  { printf "  %s›%s %s\n" "$LIGHT" "$RESET" "$1"; }
ok()    { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn()  { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$1"; }
fail()  { printf "  %s✗ error:%s %s\n" "$RED" "$RESET" "$1" >&2; exit 1; }

# Simple spinner that wraps a command; keeps the terminal quiet otherwise
spin() {
  local msg="$1"; shift
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  "$@" &
  local pid=$!
  local i=0
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      i=$(( (i + 1) % ${#frames} ))
      printf "\r  %s%s%s %s" "$MID" "${frames:$i:1}" "$RESET" "$msg"
      sleep 0.08
    done
    printf "\r\033[K"
  fi
  wait "$pid"
}

if [ -t 1 ]; then
  printf "\n"
  printf "  %s███████╗%s███████╗%s██╗     %s███████╗%s███╗   ██╗%s███████╗\n" "$BASE" "$MID" "$LIGHT" "$LIGHT" "$MID" "$BASE"
  printf "  %s██╔════╝%s██╔════╝%s██║     %s██╔════╝%s████╗  ██║%s██╔════╝\n" "$BASE" "$MID" "$LIGHT" "$LIGHT" "$MID" "$BASE"
  printf "  %s███████╗%s█████╗  %s██║     %s█████╗  %s██╔██╗ ██║%s█████╗  \n" "$BASE" "$MID" "$LIGHT" "$LIGHT" "$MID" "$BASE"
  printf "  %s╚════██║%s██╔══╝  %s██║     %s██╔══╝  %s██║╚██╗██║%s██╔══╝  \n" "$BASE" "$MID" "$LIGHT" "$LIGHT" "$MID" "$BASE"
  printf "  %s███████║%s███████╗%s███████╗%s███████╗%s██║ ╚████║%s███████╗\n" "$BASE" "$MID" "$LIGHT" "$LIGHT" "$MID" "$BASE"
  printf "  %s╚══════╝%s╚══════╝%s╚══════╝%s╚══════╝%s╚═╝  ╚═══╝%s╚══════╝%s\n" "$BASE" "$MID" "$LIGHT" "$LIGHT" "$MID" "$BASE" "$RESET"
  printf "  %smacOS installer · github.com/%s%s\n\n" "$DIM$PALE" "$REPO" "$RESET"
fi

[ "$(uname)" = "Darwin" ] || fail "Selene only runs on macOS"
command -v curl >/dev/null || fail "curl not found"
command -v hdiutil >/dev/null || fail "hdiutil not found"

step "Looking up the latest release"
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest") \
  || fail "Couldn't reach GitHub"

VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
DMG_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.dmg"' | head -1 | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')
[ -n "$DMG_URL" ] || fail "No .dmg found in the latest release"
ok "Found ${BOLD}${PALE}$VERSION${RESET}"

TMP_DIR=$(mktemp -d)
MOUNT_POINT="$TMP_DIR/mnt"
cleanup() {
  hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

download_with_progress() {
  local url="$1" out="$2" width=28
  local total cur pct filled empty bar

  total=$(curl -sIL "$url" | grep -i '^content-length' | tail -1 | tr -d '\r' | awk '{print $2}')
  curl -fL -s "$url" -o "$out" &
  local pid=$!

  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      cur=$(stat -f%z "$out" 2>/dev/null || echo 0)
      if [ -n "${total:-}" ] && [ "$total" -gt 0 ] 2>/dev/null; then
        pct=$(( cur * 100 / total ))
        [ "$pct" -gt 100 ] && pct=100
      else
        pct=0
      fi
      filled=$(( pct * width / 100 ))
      empty=$(( width - filled ))
      bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"
      printf "\r  %s%s%s %s%3d%%%s" "$LIGHT" "$bar" "$RESET" "$DIM" "$pct" "$RESET"
      sleep 0.1
    done
    printf "\r\033[K"
  fi
  wait "$pid"
}

step "Downloading Selene"
DMG_PATH="$TMP_DIR/Selene.dmg"
download_with_progress "$DMG_URL" "$DMG_PATH" || fail "Download failed"
ok "Download complete"

step "Mounting the disk image"
mkdir -p "$MOUNT_POINT"
spin "Mounting..." hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet \
  || fail "Failed to mount the .dmg"

[ -d "$MOUNT_POINT/$APP_NAME" ] || fail "Couldn't find $APP_NAME inside the disk image"

if pgrep -x "Selene" >/dev/null 2>&1; then
  step "Quitting the running copy of Selene"
  osascript -e 'quit app "Selene"' >/dev/null 2>&1 || true
  sleep 1
fi

if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
  step "Removing the previous install"
  rm -rf "$INSTALL_DIR/$APP_NAME"
fi

step "Installing to $INSTALL_DIR"
cp -R "$MOUNT_POINT/$APP_NAME" "$INSTALL_DIR/" \
  || fail "Copy failed - check permissions on $INSTALL_DIR"

hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true

step "Clearing the quarantine flag"
xattr -cr "$INSTALL_DIR/$APP_NAME"

printf "\n  %s%s✓ Selene %s installed%s\n" "$BOLD" "$GREEN" "$VERSION" "$RESET"
printf "  %sOpen it from Launchpad or Spotlight.%s\n\n" "$DIM" "$RESET"