#!/bin/bash
# Renders docs screenshots: scripts/snapshot.sh [dir]  (default docs/screenshots)
# Runs Wave --snapshot from a throwaway app bundle via `open`, because macOS only lets a LaunchServices-launched
# app become active, and inactive windows draw switches and selections grey.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(cd "$(dirname "${1:-docs/screenshots}")" && pwd)/$(basename "${1:-docs/screenshots}")"

swift build
app="$(mktemp -d)/WaveSnapshot.app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build --show-bin-path)/Wave" "$app/Contents/MacOS/Wave"
# Own bundle id, so it never touches the real app's permissions or settings.
sed 's/com.srtkio.wave</com.srtkio.wave.snapshot</' Resources/Info.plist > "$app/Contents/Info.plist"
rm -rf "$out"
open -W -n "$app" --args --snapshot "$out"
rm -rf "$(dirname "$app")"
ls "$out"
