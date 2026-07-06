#!/bin/bash
#
# Appends the freshly built release to the Sparkle appcast
# (landing/public/appcast.xml), signing the notarized DMG with the EdDSA key
# held in the release machine's keychain.
#
# Run AFTER scripts/release.sh (which resolves Sparkle's tools under build/) and
# AFTER the GitHub release DMG is uploaded, so the enclosure URL resolves. Then
# commit landing/public/appcast.xml and redeploy the landing so Sparkle sees it.
#
# Usage: scripts/update-appcast.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$ROOT/build/dist/Pinpoint.dmg"
APPCAST="$ROOT/landing/public/appcast.xml"
FEED_BASE="https://github.com/croustibat/Pinpoint/releases/download"

VERSION="$(grep -m1 'MARKETING_VERSION:' "$ROOT/project.yml" | sed -E 's/.*"([^"]+)".*/\1/')"
BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION:' "$ROOT/project.yml" | sed -E 's/.*"([^"]+)".*/\1/')"
MIN_OS="$(grep -m1 'MACOSX_DEPLOYMENT_TARGET:' "$ROOT/project.yml" | sed -E 's/.*"([^"]+)".*/\1/')"

[ -n "$VERSION" ] || { echo "✗ MARKETING_VERSION introuvable dans project.yml"; exit 1; }
[ -f "$DMG" ] || { echo "✗ DMG introuvable: $DMG — lance d'abord scripts/release.sh"; exit 1; }
[ -f "$APPCAST" ] || { echo "✗ appcast introuvable: $APPCAST"; exit 1; }

# Locate Sparkle's sign_update (resolved SPM artifact under build/, or override).
SIGN_UPDATE="${SIGN_UPDATE:-$(find "$ROOT/build" -name sign_update -type f 2>/dev/null | head -1)}"
[ -x "$SIGN_UPDATE" ] || { echo "✗ sign_update introuvable — définis SIGN_UPDATE=/chemin/vers/sign_update"; exit 1; }

if grep -q "shortVersionString>$VERSION<" "$APPCAST"; then
  echo "✓ L'appcast contient déjà la version $VERSION"
  exit 0
fi

# sign_update prints: sparkle:edSignature="…" length="…"
SIG_ATTRS="$("$SIGN_UPDATE" "$DMG")"
PUBDATE="$(date "+%a, %d %b %Y %H:%M:%S %z")"

ITEM="$(mktemp)"
cat > "$ITEM" <<EOF
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS:-15.0}</sparkle:minimumSystemVersion>
      <enclosure url="$FEED_BASE/v$VERSION/Pinpoint.dmg" $SIG_ATTRS type="application/octet-stream" />
    </item>
EOF

# Insert the new item right after the anchor comment (newest first).
sed -i '' -e "/NEWEST-ITEM-ANCHOR/r $ITEM" "$APPCAST"
rm -f "$ITEM"

echo "✓ appcast mis à jour : Pinpoint $VERSION"
echo "  → commit landing/public/appcast.xml puis redéploie la landing (vercel deploy --prod)."
