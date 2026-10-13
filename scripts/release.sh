#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]]; then
  echo "Expected an explicitly versioned release candidate in VERSION" >&2
  exit 1
fi
./scripts/build.sh
./scripts/package.sh
RELEASE="dist/releases/$VERSION"
mkdir -p "$RELEASE"
cp "dist/Raining Hell-macOS.dmg" "$RELEASE/Raining-Hell-$VERSION-macOS.dmg"
cp "dist/Raining Hell-macOS-portable.zip" "$RELEASE/Raining-Hell-$VERSION-macOS-portable.zip"
cp README.md RELEASE_NOTES.md "$RELEASE/"
(cd "$RELEASE" && shasum -a 256 "Raining-Hell-$VERSION-macOS.dmg" "Raining-Hell-$VERSION-macOS-portable.zip" README.md RELEASE_NOTES.md > SHA256SUMS.txt && shasum -a 256 -c SHA256SUMS.txt)
printf 'Local release candidate ready: %s (not published)\n' "$RELEASE"
