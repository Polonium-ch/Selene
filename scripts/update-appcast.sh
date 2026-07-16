#!/bin/bash
# Inserts a new <item> at the top of appcast.xml (newest release first).
# Used by .github/workflows/release.yml after build-and-sign-dmg.sh runs.
#
# Release notes come straight from CHANGELOG.md - the "## [<version>]"
# section scripts/release.sh promotes from "## [Unreleased]" when it bumps
# the version - so there's one source of truth for what Sparkle shows users
# in the update dialog.
set -euo pipefail

[ $# -eq 5 ] || { echo "usage: $0 <short_version> <build_number> <dmg_length> <ed_signature> <download_url>" >&2; exit 1; }

SHORT_VERSION="$1"
BUILD_NUMBER="$2"
DMG_LENGTH="$3"
ED_SIGNATURE="$4"
DOWNLOAD_URL="$5"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST="$ROOT_DIR/appcast.xml"
CHANGELOG="$ROOT_DIR/CHANGELOG.md"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

python3 - "$APPCAST" "$CHANGELOG" "$SHORT_VERSION" "$BUILD_NUMBER" "$DMG_LENGTH" "$ED_SIGNATURE" "$DOWNLOAD_URL" "$PUB_DATE" <<'PY'
import html
import re
import sys

appcast_path, changelog_path, short_version, build_number, dmg_length, ed_signature, download_url, pub_date = sys.argv[1:]

with open(changelog_path, encoding="utf-8") as f:
    changelog = f.read()

section_re = re.compile(
    rf"^## \[{re.escape(short_version)}\].*$\n(.*?)(?=^## \[|\Z)",
    re.MULTILINE | re.DOTALL,
)
match = section_re.search(changelog)
if not match or not match.group(1).strip():
    sys.exit(
        f"error: no CHANGELOG.md entry for {short_version} - "
        f"add one under '## [{short_version}]' before releasing"
    )

# Turns "### Category" + "- item" markdown into <h2>/<ul><li> HTML so
# Sparkle's update dialog can render it directly as the item description.
body_lines = []
in_list = False
for line in match.group(1).splitlines():
    line = line.rstrip()
    heading = re.match(r"^### (.+)$", line)
    item = re.match(r"^- (.+)$", line)
    if heading:
        if in_list:
            body_lines.append("</ul>")
            in_list = False
        body_lines.append(f"<h2>{html.escape(heading.group(1))}</h2>")
    elif item:
        if not in_list:
            body_lines.append("<ul>")
            in_list = True
        body_lines.append(f"<li>{html.escape(item.group(1))}</li>")
if in_list:
    body_lines.append("</ul>")
description_html = "\n".join(body_lines)

item = f"""    <item>
      <title>Version {short_version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{build_number}</sparkle:version>
      <sparkle:shortVersionString>{short_version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
{description_html}
      ]]></description>
      <enclosure url="{download_url}" sparkle:edSignature="{ed_signature}" length="{dmg_length}" type="application/octet-stream"/>
    </item>"""

with open(appcast_path, encoding="utf-8") as f:
    content = f.read()

marker = "    <item>"
idx = content.index(marker)
content = content[:idx] + item + "\n" + content[idx:]

with open(appcast_path, "w", encoding="utf-8") as f:
    f.write(content)

print(f"Inserted Version {short_version} into {appcast_path}")
PY
