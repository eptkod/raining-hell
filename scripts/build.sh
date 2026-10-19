#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Raining Hell.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
swift scripts/icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
python3 scripts/sounds.py "$APP/Contents/Resources/Sounds"
cp README.md RELEASE_NOTES.md "$APP/Contents/Resources/"
SDK="$(xcrun --show-sdk-path)"
# Apple Silicon only: current Command Line Tools no longer ship the x86_64 Swift runtime.
for ARCH in arm64; do
  swiftc -O -wmo -sdk "$SDK" -target "$ARCH-apple-macosx12.0" Sources/World.swift Sources/Structure.swift Sources/Mission.swift Sources/Support.swift Sources/Drone.swift Sources/Fire.swift Sources/Water.swift Sources/Keybinds.swift Sources/Levels.swift Sources/Landmarks.swift Sources/Fronts.swift Sources/Audio.swift Sources/GameView.swift Sources/FireView.swift Sources/WaterView.swift Sources/main.swift -o "build/RainingHell-$ARCH" -framework AppKit -framework AVFoundation
 done
cp build/RainingHell-arm64 "$APP/Contents/MacOS/RainingHell"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Raining Hell</string>
<key>CFBundleDisplayName</key><string>Raining Hell</string>
<key>CFBundleIdentifier</key><string>games.raininghell.prototype</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleExecutable</key><string>RainingHell</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Raining Hell · Sandbox prototype</string>
</dict></plist>
PLIST
if [ -f build/AppIcon.icns ]; then cp build/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$APP"
"$APP/Contents/MacOS/RainingHell" --self-test
swiftc -O -wmo Sources/World.swift Sources/Structure.swift Sources/Mission.swift Sources/Support.swift Sources/Drone.swift Sources/Fire.swift Sources/Water.swift Sources/Keybinds.swift Sources/Levels.swift Sources/Landmarks.swift Sources/Fronts.swift Tests/PhysicsTests.swift -o build/PhysicsTests
build/PhysicsTests
swiftc -O -wmo Sources/World.swift Sources/Structure.swift Sources/Mission.swift Sources/Support.swift Sources/Drone.swift Sources/Fire.swift Sources/Water.swift Sources/Keybinds.swift Sources/Levels.swift Sources/Landmarks.swift Sources/Fronts.swift Tests/AudioEvents.swift -o build/AudioEvents
build/AudioEvents
python3 Tests/audio_assets.py "$APP/Contents/Resources/Sounds"
swiftc -O -wmo Tests/AudioAssets.swift -parse-as-library -framework AVFoundation -o build/AudioAssets
build/AudioAssets "$APP/Contents/Resources/Sounds"
printf 'Built Apple Silicon macOS app: %s\n' "$APP"
