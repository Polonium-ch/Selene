#!/bin/bash
# Inserts a new <item> at the top of appcast.xml (newest release first).
# Used by .github/workflows/release.yml after build-and-sign-dmg.sh runs.
set -euo pipefail

[ $# -eq 5 ] || { echo "usage: $0 <short_version> <build_number> <dmg_length> <ed_signature> <download_url>" >&2; exit 1; }

SHORT_VERSION="$1"
BUILD_NUMBER="$2"
DMG_LENGTH="$3"
ED_SIGNATURE="$4"
DOWNLOAD_URL="$5"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST="$ROOT_DIR/appcast.xml"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

ITEM="    <item>
      <title>Version $SHORT_VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url=\"$DOWNLOAD_URL\" sparkle:edSignature=\"$ED_SIGNATURE\" length=\"$DMG_LENGTH\" type=\"application/octet-stream\"/>
    </item>"

python3 - "$APPCAST" "$ITEM" <<'PY'
import sys

path, item = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()

marker = "    <item>"
idx = content.index(marker)
content = content[:idx] + item + "\n" + content[idx:]

with open(path, "w") as f:
    f.write(content)
PY

echo "Inserted Version $SHORT_VERSION into $APPCAST"
