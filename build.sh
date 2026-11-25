#!/bin/bash
# Camera permission only works from a bundle with NSCameraUsageDescription, so `swift run` alone can't see the camera.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
bin="$(swift build -c release --show-bin-path)/Wave"

rm -rf build/Wave.app
mkdir -p build/Wave.app/Contents/MacOS
cp "$bin" build/Wave.app/Contents/MacOS/Wave
cp Resources/Info.plist build/Wave.app/Contents/Info.plist
# Regenerate the icon only when its script changes.
if [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then swift scripts/make-icon.swift build/AppIcon.icns; fi
mkdir -p build/Wave.app/Contents/Resources
cp build/AppIcon.icns build/Wave.app/Contents/Resources/AppIcon.icns
codesign --force --deep -s - build/Wave.app

# Keep a copy in Applications so Wave opens from Launchpad, Spotlight and Finder like any app.
pkill -x Wave 2>/dev/null || true
rm -rf /Applications/Wave.app
ditto build/Wave.app /Applications/Wave.app

echo "/Applications/Wave.app"
