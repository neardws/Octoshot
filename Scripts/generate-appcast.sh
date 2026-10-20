#!/usr/bin/env bash
# Sign a notarized Octoshot DMG with Sparkle EdDSA and write website/public/appcast.xml for GitHub Pages.
#
# Environment:
#   VERSION         Marketing version (optional; inferred from DMG name)
#   DMG_PATH        Notarized DMG (default: dist/Octoshot-v$VERSION-macOS.dmg)
#   SPARKLE_KEY     Private EdDSA key file (Sparkle export format); default ~/octoshot-private/sparkle/eddsa_priv.key
#   DOWNLOAD_URL    enclosure URL (default: GitHub Release asset URL)
#
# Does not create a GitHub Release or upload assets.
set -euo pipefail
cd "$(dirname "$0")/.."

bash Scripts/fetch-sparkle.sh
SP=".build/sparkle/2.10.0"

KEY="${SPARKLE_KEY:-$HOME/octoshot-private/sparkle/eddsa_priv.key}"
if [ ! -f "$KEY" ]; then
  echo "❌ Sparkle private key not found: $KEY"
  echo "   Generate on macOS: bash Scripts/generate-sparkle-keys.sh"
  echo "   Or set SPARKLE_KEY to your exported eddsa_priv.key path."
  exit 1
fi

VERSION="${VERSION:-}"
DMG_PATH="${DMG_PATH:-}"
if [ -z "$DMG_PATH" ] && [ -n "$VERSION" ]; then
  DMG_PATH="dist/Octoshot-v${VERSION}-macOS.dmg"
fi
if [ -z "$DMG_PATH" ]; then
  DMG_PATH=$(ls -t dist/Octoshot-v*-macOS.dmg 2>/dev/null | grep -v unsigned | head -1 || true)
fi
[ -n "${DMG_PATH:-}" ] && [ -f "$DMG_PATH" ] || { echo "❌ DMG not found (set DMG_PATH or VERSION)"; exit 1; }

VERSION="${VERSION:-$(basename "$DMG_PATH" | sed -E 's/^Octoshot-v//; s/-macOS\.dmg$//; s/-unsigned$//')}"
DMG_BASENAME="Octoshot-v${VERSION}-macOS.dmg"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/neardws/Octoshot/releases/download/v${VERSION}/${DMG_BASENAME}}"

STAGE=$(mktemp -d /tmp/octoshot-appcast.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
cp "$DMG_PATH" "$STAGE/$DMG_BASENAME"
NOTES="docs/release-notes/v${VERSION}.md"
if [ -f "$NOTES" ]; then
  cp "$NOTES" "$STAGE/Octoshot-v${VERSION}.md"
fi

"$SP/bin/generate_appcast" \
  --ed-key-file "$KEY" \
  --download-url-prefix "https://github.com/neardws/Octoshot/releases/download/v${VERSION}/" \
  --link "https://www.neardws.com/Octoshot/" \
  --embed-release-notes \
  -o "$STAGE/appcast.xml" \
  "$STAGE"

python3 Scripts/check-arm64-appcast.py "$STAGE/appcast.xml"

mkdir -p website/public
cp "$STAGE/appcast.xml" website/public/appcast.xml

python3 - "$DOWNLOAD_URL" <<'PY'
import re
import sys
from pathlib import Path

url = sys.argv[1]
path = Path("website/public/appcast.xml")
text = path.read_text()
text2, n = re.subn(r'(<enclosure[^>]*\surl=")[^"]+(")', rf"\1{url}\2", text, count=1)
path.write_text(text2 if n else text)
print(f"✅ website/public/appcast.xml (enclosure → {url})" if n else "⚠️  no enclosure rewritten")
PY

head -40 website/public/appcast.xml
