#!/bin/bash
#
# Build local + installation directe dans /Applications, SANS notarisation.
#
# Pour tester une nouvelle version sans ouvrir Xcode et sans reperdre
# l'autorisation « Enregistrement de l'écran » : on signe avec la MÊME identité
# Developer ID que l'app déjà installée, donc le designated requirement reste
# identique et macOS conserve le grant TCC (le matching se fait sur l'identité
# de signature + bundle id, pas sur le cdhash).
#
# Différence avec release.sh : pas de notarisation, pas de DMG. Build local pur.
#
# Usage : scripts/install-local.sh
set -euo pipefail

TEAM="MMJD6CLKNQ"
IDENTITY="Developer ID Application: Baptiste Bouillot (${TEAM})"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/release"
APP="$DERIVED/Build/Products/Release/Pinpoint.app"
DEST="/Applications/Pinpoint.app"
BIN="/Applications/Pinpoint.app/Contents/MacOS/Pinpoint"

cd "$ROOT"

echo "▸ Génération du projet"
xcodegen generate >/dev/null

echo "▸ Build Release (non signé)"
xcodebuild -scheme Pinpoint -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build >/dev/null

echo "▸ Signature Developer ID + hardened runtime"
# Signer d'abord le code imbriqué (frameworks/dylibs), puis le bundle.
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" -depth \( -name "*.framework" -o -name "*.dylib" \) -print0 \
    | while IFS= read -r -d '' item; do
        codesign --force --options runtime --sign "$IDENTITY" "$item"
      done
fi
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▸ Fermeture de l'app si elle tourne"
osascript -e 'tell application "Pinpoint" to quit' 2>/dev/null || true
pkill -f "$BIN" 2>/dev/null || true
n=0
while pgrep -f "$BIN" >/dev/null 2>&1 && [ "$n" -lt 200 ]; do n=$((n + 1)); done

echo "▸ Remplacement dans /Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "▸ Relance"
open "$DEST"

echo "✓ Installé : $DEST"
codesign -dvv "$DEST" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier" || true
