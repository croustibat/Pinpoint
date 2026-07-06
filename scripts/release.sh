#!/bin/bash
#
# Builds, signs (Developer ID), notarizes and packages Pinpoint as a signed DMG.
#
# Prerequisites (one-time): store notarization credentials in a keychain profile
#   xcrun notarytool store-credentials pinpoint-notary \
#     --apple-id "<your-apple-id>" --team-id MMJD6CLKNQ --password "<app-specific-password>"
#   (or use --key / --key-id / --issuer for an App Store Connect API key)
#
# Usage: scripts/release.sh
set -euo pipefail

TEAM="MMJD6CLKNQ"
IDENTITY="Developer ID Application: Baptiste Bouillot (${TEAM})"
NOTARY_PROFILE="${NOTARY_PROFILE:-pinpoint-notary}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/release"
APP="$DERIVED/Build/Products/Release/Pinpoint.app"
DIST="$ROOT/build/dist"
ZIP="$DIST/Pinpoint.zip"
DMG="$DIST/Pinpoint.dmg"

cd "$ROOT"
mkdir -p "$DIST"
rm -f "$ZIP" "$DMG"

echo "▸ Generating project"
xcodegen generate >/dev/null

echo "▸ Building Release (unsigned)"
xcodebuild -scheme Pinpoint -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build >/dev/null

echo "▸ Signing with Developer ID + hardened runtime"
# Sign nested code deepest-first, then the app bundle. Sparkle ships a helper
# app (Updater.app), XPC services and a bare Autoupdate tool that each need
# their own signature under the hardened runtime, before the framework and app.
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" -depth \( -name "*.xpc" -o -name "*.app" \) -print0 \
    | while IFS= read -r -d '' item; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
      done
  find "$APP/Contents/Frameworks" -name "Autoupdate" -type f -print0 \
    | while IFS= read -r -d '' item; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
      done
  find "$APP/Contents/Frameworks" -depth \( -name "*.framework" -o -name "*.dylib" \) -print0 \
    | while IFS= read -r -d '' item; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
      done
fi
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▸ Notarizing the app"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "▸ Building DMG"
create-dmg \
  --volname "Pinpoint" \
  --window-size 540 380 \
  --icon-size 100 \
  --icon "Pinpoint.app" 140 190 \
  --app-drop-link 400 190 \
  "$DMG" "$APP"

echo "▸ Signing + notarizing the DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Gatekeeper assessment"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true
codesign --verify --strict --verbose=2 "$APP"

echo "✓ Done: $DMG"
