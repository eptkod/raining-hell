#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Raining Hell.app"
VERSION="$(cat VERSION)"
if [ ! -d "$APP" ]; then ./scripts/build.sh; fi
mkdir -p build/dmg build/portable
# Replace only generated staging folders, never user applications.
if [ -d "build/dmg/Raining Hell.app" ]; then rm -rf "build/dmg/Raining Hell.app"; fi
PORTABLE="build/portable/Raining Hell $VERSION"
if [ -d "$PORTABLE" ]; then rm -rf "$PORTABLE"; fi
mkdir -p "$PORTABLE"
ditto "$APP" "build/dmg/Raining Hell.app"
ditto "$APP" "$PORTABLE/Raining Hell.app"
ln -sfn /Applications build/dmg/Applications
cp README.md "build/dmg/Read Me.md"
cp RELEASE_NOTES.md build/dmg/
cp README.md RELEASE_NOTES.md "$PORTABLE/"
hdiutil create -volname "Raining Hell $VERSION" -srcfolder build/dmg -ov -format UDZO "dist/Raining Hell-macOS.dmg"
# ditto can update existing archives: remove the known output to avoid stale files.
if [ -f "dist/Raining Hell-macOS-portable.zip" ]; then rm "dist/Raining Hell-macOS-portable.zip"; fi
ditto -c -k --sequesterRsrc --keepParent "$PORTABLE" "dist/Raining Hell-macOS-portable.zip"
codesign --verify --deep --strict "$APP"
hdiutil verify "dist/Raining Hell-macOS.dmg"
unzip -tq "dist/Raining Hell-macOS-portable.zip"
(cd dist && shasum -a 256 "Raining Hell-macOS.dmg" "Raining Hell-macOS-portable.zip" > SHA256SUMS.txt)
printf 'Created DMG and portable ZIP in dist/\n'
