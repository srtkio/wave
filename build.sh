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
codesign --force --deep -s - build/Wave.app

echo "$(pwd)/build/Wave.app"
