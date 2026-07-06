#!/bin/bash
#
# Bumps the Homebrew cask (croustibat/homebrew-tap) to the freshly built release.
#
# Reads MARKETING_VERSION from project.yml and the sha256 of the notarized DMG
# produced by scripts/release.sh, then updates, commits and pushes
# Casks/pinpoint.rb in the tap repo.
#
# Run this AFTER scripts/release.sh and AFTER the GitHub release DMG is uploaded
# (`gh release create v<version> … build/dist/Pinpoint.dmg`), so the cask URL
# resolves for users. The sha256 is taken from the local DMG, which is byte-for-
# byte the uploaded asset.
#
# Usage: scripts/update-cask.sh
set -euo pipefail

TAP_SLUG="${TAP_SLUG:-croustibat/homebrew-tap}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="$ROOT/build/dist/Pinpoint.dmg"

VERSION="$(grep -m1 'MARKETING_VERSION:' "$ROOT/project.yml" | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$VERSION" ] || { echo "✗ MARKETING_VERSION introuvable dans project.yml"; exit 1; }
[ -f "$DMG" ] || { echo "✗ DMG introuvable: $DMG — lance d'abord scripts/release.sh"; exit 1; }

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

echo "▸ pinpoint $VERSION"
echo "  sha256 $SHA"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --depth 1 "https://github.com/${TAP_SLUG}.git" "$WORK" >/dev/null 2>&1

CASK="$WORK/Casks/pinpoint.rb"
[ -f "$CASK" ] || { echo "✗ Cask absent du tap: $CASK"; exit 1; }

sed -i '' -E "s/^  version \"[^\"]+\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \"[^\"]+\"/  sha256 \"$SHA\"/" "$CASK"

if git -C "$WORK" diff --quiet; then
  echo "✓ Cask déjà à jour ($VERSION)"
  exit 0
fi

git -C "$WORK" commit -qam "pinpoint $VERSION"
git -C "$WORK" push -q origin HEAD
echo "✓ Cask poussé: ${TAP_SLUG} → pinpoint $VERSION"
